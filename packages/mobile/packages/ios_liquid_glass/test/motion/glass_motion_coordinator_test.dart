import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

class _Toggle extends StatefulWidget {
  const _Toggle({required this.children, this.animation, this.row = false, this.container = true});

  final List<Widget> Function(bool shown) children;
  final GlassAnimation? animation;
  final bool row;
  final bool container;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool shown = true;

  void toggle() => setState(() => shown = !shown);

  @override
  Widget build(BuildContext context) {
    final children = widget.children(shown);
    final Widget flex = widget.row ? Row(mainAxisSize: MainAxisSize.min, children: children) : Column(mainAxisSize: MainAxisSize.min, children: children);
    final container = widget.container ? GlassEffectContainer(child: flex) : flex;
    final animation = widget.animation;
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(child: animation == null ? container : GlassAnimationScope(animation: animation, child: container)),
      ),
    );
  }
}

Widget _block({Key? key, double width = 250, double height = 88, Widget? child}) =>
    GlassEffect(key: key, child: SizedBox(width: width, height: height, child: child));

Iterable<LiquidGlassLayer> _layers(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer));

double? _visibility(WidgetTester tester) => _layers(tester).map((layer) => layer.visibility?.value).whereType<double>().firstOrNull;

GlassMember _member(WidgetTester tester, [Finder? glass]) =>
    tester.renderObject<RenderGlassMemberBox>(find.descendant(of: glass ?? find.byType(GlassEffect), matching: find.byType(GlassMemberBox)).first).member;

Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  testWidgets('glass present at the first frame does not animate in', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block()]));
    expect(_layers(tester).length, 1);
    expect(find.byType(LiquidGlass), findsOneWidget);
  });

  testWidgets('inserted glass materializes in its own layer, then joins the container', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump();
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_layers(tester).length, 2);
    expect(_visibility(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    final early = _visibility(tester)!;
    await tester.pump(const Duration(milliseconds: 150));
    final later = _visibility(tester)!;
    expect(early, inExclusiveRange(0, later));
    expect(later, lessThan(1));
    await tester.pumpAndSettle();
    expect(_layers(tester).length, 1);
  });

  testWidgets('removed glass leaves a ghost in the same frame, with its content snapshot, and it is dropped after', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(_visibility(tester), 1);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_visibility(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(_layers(tester).length, 1);
  });

  testWidgets('a ghost stays where its glass was on screen when the container shrinks around the removal', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    final before = tester.getRect(find.byType(GlassEffect));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(tester.getSize(find.byType(GlassEffectContainer)), Size.zero);
    expect(tester.getRect(find.byType(RawImage)).center, before.center);
  });

  testWidgets('disappearing is faster than appearing under the same spring', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final out = _visibility(tester)!;
    await tester.pumpAndSettle();
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final into = _visibility(tester)!;
    expect(1 - out, greaterThan(into));
  });

  testWidgets('GlassAnimation.none and the identity transition change at once', (tester) async {
    await tester.pumpWidget(_Toggle(animation: GlassAnimation.none, children: (shown) => [if (shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsNothing);
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_layers(tester).length, 1);
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) const GlassEffect(transition: GlassEffectTransition.identity, child: SizedBox(width: 10, height: 10))]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('identity glass inserted into a laid-out container appears at once', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) const GlassEffect(transition: GlassEffectTransition.identity, child: SizedBox(width: 10, height: 10))]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(_layers(tester).length, 1);
    expect(_visibility(tester), isNull);
  });

  testWidgets('removing glass while it appears continues from its current visibility', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final before = _visibility(tester)!;
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_visibility(tester), closeTo(before, 1e-9));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('a container removed while its glass animates disposes cleanly', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilding during an animation does not restart it', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_ToggleState>(find.byType(_Toggle));
    state.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final before = _visibility(tester)!;
    state.toggle();
    state.toggle();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_visibility(tester), greaterThan(before));
  });

  testWidgets('switching Reduce Motion during an animation neither restarts nor stops it', (tester) async {
    addTearDown(GlassAccessibility.debugReset);
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final before = _visibility(tester)!;
    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 16));
    final after = _visibility(tester)!;
    expect(after, greaterThan(before));
    expect(after, lessThan(1));
    await tester.pumpAndSettle();
    expect(_layers(tester).length, 1);
  });

  testWidgets('a ghost draws in its own layer, so sixteen glasses, one leaving and one arriving never share one group', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [
      for (var i = 0; i < 15; i++) _block(key: ValueKey(i), width: 20, height: 10),
      if (shown) _block(key: const ValueKey('leaving'), width: 20, height: 10),
      if (!shown) _block(key: const ValueKey('arriving'), width: 20, height: 10),
    ]));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    final ghost = find.ancestor(of: find.byType(RawImage), matching: find.byType(LiquidGlassLayer)).first;
    expect(ghost, findsOneWidget);
    expect(find.descendant(of: ghost, matching: find.byType(GlassEffect)), findsNothing);
    expect(find.byType(GlassEffect), findsNWidgets(16));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resized glass springs its drawn rect with no widget rebuilds while it moves', (tester) async {
    var builds = 0;
    var wide = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return GlassEffectContainer(
            child: GlassEffect(
              child: Builder(builder: (context) {
                builds++;
                return SizedBox(width: wide ? 300 : 100, height: 60);
              }),
            ),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final box = tester.renderObject<RenderGlassMemberBox>(find.byType(GlassMemberBox));
    expect(box.member.drawn!.width, 100);
    final centre = _onScreen(box.member).center;
    rebuild(() => wide = true);
    await tester.pump();
    final buildsAfterChange = builds;
    expect(box.member.drawn!.width, closeTo(100, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = box.member.drawn!.width;
    expect(mid, inExclusiveRange(100, 300));
    expect(_onScreen(box.member).center.dx, closeTo(centre.dx, 1e-6));
    expect(box.member.resolve(box).width, mid);
    await tester.pump(const Duration(milliseconds: 100));
    expect(box.member.drawn!.width, greaterThan(mid));
    expect(builds, buildsAfterChange);
    await tester.pumpAndSettle();
    expect(box.member.drawn!.width, 300);
  });

  testWidgets('hit testing uses the final layout while the glass is still moving', (tester) async {
    var taps = 0;
    var right = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return GlassEffectContainer(
            child: Padding(
              padding: EdgeInsets.only(left: right ? 200 : 0),
              child: GlassEffect(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const SizedBox(width: 80, height: 80))),
            ),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    rebuild(() => right = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final box = tester.renderObject<RenderGlassMemberBox>(find.byType(GlassMemberBox));
    expect(box.member.drawn!.left, inExclusiveRange(0, 200));
    await tester.tapAt(const Offset(240, 40));
    await tester.pump();
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a list scrolled inside a container moves its glass with the list at once, with no spring', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            height: 300,
            width: 200,
            child: ListView(controller: controller, children: [for (var i = 0; i < 12; i++) _block(key: ValueKey(i), width: 200, height: 60)]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester, find.byKey(const ValueKey(2)));
    final before = _onScreen(member);
    expect(before.top, closeTo(tester.getRect(find.byKey(const ValueKey(2))).top, 1e-6));
    controller.jumpTo(50);
    await tester.pump();
    expect(_onScreen(member).top, closeTo(before.top - 50, 1e-6));
    expect(_onScreen(member).top, closeTo(tester.getRect(find.byKey(const ValueKey(2))).top, 1e-6));
    expect(member.isMoving, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).top, closeTo(before.top - 50, 1e-6));
    expect(_visibility(tester), isNull);
  });

  testWidgets('a glass resized by a rebuild while its list scrolls follows the scroll exactly and springs only its size', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var wide = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            height: 300,
            width: 300,
            child: StatefulBuilder(builder: (context, setState) {
              rebuild = setState;
              return ListView(controller: controller, children: [
                for (var i = 0; i < 12; i++)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _block(key: ValueKey(i), width: i == 2 && wide ? 200 : 100, height: 60),
                  ),
              ]);
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester, find.byKey(const ValueKey(2)));
    final before = _onScreen(member);
    rebuild(() => wide = true);
    controller.jumpTo(50);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final layout = tester.getRect(find.byKey(const ValueKey(2)));
    final drawn = _onScreen(member);
    expect(layout.top, closeTo(before.top - 50, 1e-6));
    expect(drawn.top, closeTo(layout.top, 1e-6));
    expect(drawn.width, inExclusiveRange(100, 200));
    await tester.pumpAndSettle();
    expect(_onScreen(member), tester.getRect(find.byKey(const ValueKey(2))));
  });

  testWidgets('a glass dragged by setState holds still in its first frame, then sits on its layout within 0.5 pt in every frame', (tester) async {
    var x = 0.0;
    late StateSetter drag;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        drag = setState;
        return Stack(children: [
          Positioned(left: x, top: 100, child: _block(key: const ValueKey('thumb'), width: 60, height: 40, child: Text('${x.round()}'))),
        ]);
      }),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    var previous = tester.getRect(find.byKey(const ValueKey('thumb')));
    for (var i = 0; i < 12; i++) {
      drag(() => x += 15);
      await tester.pump(const Duration(milliseconds: 16));
      final layout = tester.getRect(find.byKey(const ValueKey('thumb')));
      final drawn = _onScreen(member);
      if (i == 0) {
        expect(drawn.left, closeTo(previous.left, 0.5));
        expect(member.isFollowing, isFalse);
      } else {
        expect(drawn.left, closeTo(layout.left, 0.5));
        expect(drawn.top, closeTo(layout.top, 0.5));
        expect(member.isFollowing, isTrue);
      }
      previous = layout;
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(member.isMoving, isFalse);
    expect(_onScreen(member), tester.getRect(find.byKey(const ValueKey('thumb'))));
  });

  testWidgets('a glass moved by an app animation every frame sits on its layout within 0.5 pt from the animation\'s second moving frame', (tester) async {
    final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            width: 400,
            height: 100,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Padding(
                padding: EdgeInsets.only(left: controller.value * 200),
                child: Align(alignment: Alignment.topLeft, child: _block(key: const ValueKey('moved'), width: 80, height: 60)),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    controller.forward();
    var moved = 0;
    var last = tester.getRect(find.byKey(const ValueKey('moved')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final layout = tester.getRect(find.byKey(const ValueKey('moved')));
      if (layout != last) moved++;
      if (moved >= 2 && layout != last) expect(_onScreen(member).left, closeTo(layout.left, 0.5));
      last = layout;
    }
    expect(moved, greaterThan(10));
    expect(_onScreen(member).left, closeTo(200, 0.5));
  });

  testWidgets('a single change springs, and so do changes inside withGlassAnimation on back-to-back frames', (tester) async {
    var left = 0.0;
    late StateSetter move;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            width: 400,
            height: 100,
            child: StatefulBuilder(builder: (context, setState) {
              move = setState;
              return Padding(padding: EdgeInsets.only(left: left), child: Align(alignment: Alignment.topLeft, child: _block(key: const ValueKey('glass'), width: 80, height: 60)));
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    move(() => left = 100);
    await tester.pump();
    expect(_onScreen(member).left, closeTo(0, 1e-6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(0, 100));
    expect(member.isFollowing, isFalse);
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(100, 1e-6));
    withGlassAnimation(GlassAnimation.defaultSpring, () => move(() => left = 150));
    await tester.pump(const Duration(milliseconds: 16));
    withGlassAnimation(GlassAnimation.defaultSpring, () => move(() => left = 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_onScreen(member).left, lessThan(150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(100, 200));
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(200, 1e-6));
  });

  testWidgets('a drag is followed, and a toggle after its release springs again', (tester) async {
    var x = 0.0;
    late StateSetter drag;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        drag = setState;
        return Stack(children: [
          Positioned(left: x, top: 100, child: _block(key: const ValueKey('thumb'), width: 60, height: 40)),
        ]);
      }),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    for (var i = 0; i < 6; i++) {
      drag(() => x += 15);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_onScreen(member).left, closeTo(90, 0.5));
    await tester.pump(const Duration(milliseconds: 200));
    drag(() => x = 200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_onScreen(member).left, closeTo(90, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(90, 200));
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(200, 1e-6));
  });

  testWidgets('a glass removed after its list scrolled leaves its ghost where the glass was on screen', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var shown = true;
    late StateSetter remove;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            width: 300,
            height: 400,
            child: StatefulBuilder(builder: (context, setState) {
              remove = setState;
              return ListView(controller: controller, children: [
                for (var i = 0; i < 8; i++)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [if (i != 2 || shown) _block(key: ValueKey(i), width: 100, height: 60)]),
                  ),
              ]);
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    controller.jumpTo(60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final onScreen = tester.getRect(find.byKey(const ValueKey(2)));
    remove(() => shown = false);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.getRect(find.byType(RawImage)).top, closeTo(onScreen.top, 0.5));
  });

  testWidgets('a standalone glass removed after its list scrolled leaves its ghost where the glass was on screen', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var shown = true;
    late StateSetter remove;
    await tester.pumpWidget(MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 400,
            child: StatefulBuilder(builder: (context, setState) {
              remove = setState;
              return ListView(controller: controller, children: [
                for (var i = 0; i < 8; i++)
                  Padding(padding: const EdgeInsets.all(8), child: Row(children: [if (i != 2 || shown) _block(key: ValueKey(i), width: 100, height: 60)])),
              ]);
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    controller.jumpTo(60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final onScreen = tester.getRect(find.byKey(const ValueKey(2)));
    remove(() => shown = false);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.getRect(find.byType(RawImage)).top, closeTo(onScreen.top, 0.5));
  });

  testWidgets('glass keeps its place on screen when a sibling is inserted and the centred container re-centres, then springs to its new place', (tester) async {
    await tester.pumpWidget(_Toggle(row: true, children: (shown) => [
      _block(key: const ValueKey('a'), width: 100, height: 60),
      if (!shown) _block(key: const ValueKey('b'), width: 100, height: 60),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester, find.byKey(const ValueKey('a')));
    final before = _onScreen(member);
    expect(before, tester.getRect(find.byKey(const ValueKey('a'))));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    final after = tester.getRect(find.byKey(const ValueKey('a')));
    expect(after.left, closeTo(before.left - 50, 1e-6));
    expect(_onScreen(member).left, closeTo(before.left, 1e-6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(after.left, before.left));
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(after.left, 1e-6));
  });

  testWidgets('standalone glass inserted later materializes, and glass built with its page appears at once', (tester) async {
    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_visibility(tester), 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(_visibility(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_visibility(tester), 1);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (context) => Center(child: _block(key: const ValueKey('page')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final page = find.descendant(of: find.byKey(const ValueKey('page')), matching: find.byType(LiquidGlassLayer));
    expect(tester.widget<LiquidGlassLayer>(page).visibility!.value, 1);
  });

  testWidgets('removed standalone glass dematerializes in the nearest Overlay, with its content snapshot', (tester) async {
    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    final before = tester.getRect(find.byType(GlassEffect));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(GlassEffect), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.getRect(find.byType(RawImage)).center, before.center);
    expect(find.ancestor(of: find.byType(RawImage), matching: find.byType(Overlay)), findsWidgets);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_visibility(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a container removed while a ghost is in flight disposes cleanly', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    final coordinator = tester.widget<GlassContainerScope>(find.byType(GlassContainerScope)).coordinator;
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(coordinator.ghosts, hasLength(1));
    final ui.Image image = coordinator.ghosts.single.snapshot!;
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(image.debugDisposed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a standalone ghost replaced with the whole app mid-flight disposes its snapshot and leaves no ticker', (tester) async {
    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    final ui.Image image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(image.debugDisposed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the standalone ghost overlay entry is removed once unused and no ghost remains', (tester) async {
    final layer = find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_OverlayGhostLayer');
    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
    await tester.pump(const Duration(seconds: 1));
    final before = layer.evaluate().length;
    expect(before, 1);
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(RawImage), findsOneWidget);
    expect(layer, findsNWidgets(before));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(layer, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a container with glass builds without a Directionality ancestor', (tester) async {
    await tester.pumpWidget(GlassTheme(data: const GlassThemeData(brightness: Brightness.dark), child: GlassEffectContainer(child: _block())));
    expect(tester.takeException(), isNull);
    expect(find.byType(GlassEffect), findsOneWidget);
  });

  testWidgets('glass removed together with its parent disappears at once', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) Padding(padding: const EdgeInsets.all(1), child: _block())]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('standalone glass takes its material from its drawn size on every frame of a resize, with no rebuild', (tester) async {
    var tall = false;
    var builds = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return GlassEffect(
            child: Builder(builder: (context) {
              builds++;
              return SizedBox(width: 300, height: tall ? 200 : 44);
            }),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    expect(member.material!.side, 44);
    rebuild(() => tall = true);
    await tester.pump();
    final buildsAfterChange = builds;
    final sides = <double>[];
    final settings = <LiquidGlassSettings>[];
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      sides.add(member.material!.side);
      settings.add(member.material!.settings);
      expect(member.material!.side, closeTo(member.drawnSize!.shortestSide, 0.5));
    }
    expect(sides.first, inExclusiveRange(44, 200));
    expect(sides.last, greaterThan(sides.first));
    expect(settings.first, isNot(settings.last));
    expect(builds, buildsAfterChange);
    await tester.pumpAndSettle();
    expect(member.material!.side, 200);
  });

  testWidgets('visibility never rises after a removal, even right after insertion', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_ToggleState>(find.byType(_Toggle));
    state.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    state.toggle();
    await tester.pump();
    var last = _visibility(tester)!;
    while (find.byType(LiquidGlassLayer).evaluate().length > 1) {
      await tester.pump(const Duration(milliseconds: 8));
      final now = _visibility(tester);
      if (now == null) break;
      expect(now, lessThanOrEqualTo(last + 1e-12));
      last = now;
    }
  });

  testWidgets('glass moved to another container with a GlobalKey stays visible and leaves no ghost', (tester) async {
    final key = GlobalKey();
    var left = true;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        final glass = GlassEffect(key: key, child: const SizedBox(width: 80, height: 40));
        return Row(children: [
          GlassEffectContainer(child: SizedBox(width: 100, height: 60, child: left ? glass : null)),
          GlassEffectContainer(child: SizedBox(width: 100, height: 60, child: left ? null : glass)),
        ]);
      }),
    ));
    await tester.pump(const Duration(seconds: 1));
    rebuild(() => left = false);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(_member(tester).presence, GlassPresence.present);
    expect(_visibility(tester), isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a container glass removed while its route is covered goes at once, and no frame shows it after the pop', (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(_Covered(shown: shown, container: true));
    await tester.pump(const Duration(seconds: 1));
    final coordinator = tester.widget<GlassContainerScope>(find.byType(GlassContainerScope)).coordinator;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (context) => const ColoredBox(color: Color(0xFF0000FF))));
    await tester.pumpAndSettle();
    shown.value = false;
    await tester.pump();
    expect(coordinator.hasGhosts, isFalse);
    expect(find.byType(RawImage, skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    navigator.pop();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(find.byType(LiquidGlass, skipOffstage: false), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a standalone glass removed while its route is covered goes at once, with no ghost over the covering route', (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(_Covered(shown: shown, container: false));
    await tester.pump(const Duration(seconds: 1));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (context) => const ColoredBox(color: Color(0xFF0000FF))));
    await tester.pumpAndSettle();
    shown.value = false;
    await tester.pump();
    expect(find.byType(RawImage, skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    navigator.pop();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      expect(find.byType(LiquidGlass, skipOffstage: false), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ghost in flight when its route is covered is dropped, so the pop shows no frame of it', (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(_Covered(shown: shown, container: true));
    await tester.pump(const Duration(seconds: 1));
    final coordinator = tester.widget<GlassContainerScope>(find.byType(GlassContainerScope)).coordinator;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    shown.value = false;
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 16));
    navigator.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => const ColoredBox(color: Color(0xFF0000FF)),
    ));
    await tester.pump();
    await tester.pump();
    expect(coordinator.hasGhosts, isFalse);
    await tester.pump(const Duration(seconds: 1));
    navigator.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a glass inserted while its route is covered is present at once when the route shows again', (tester) async {
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    await tester.pumpWidget(_Covered(shown: shown, container: true));
    await tester.pump(const Duration(seconds: 1));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (context) => const ColoredBox(color: Color(0xFF0000FF))));
    await tester.pumpAndSettle();
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    navigator.pop();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(LiquidGlass, skipOffstage: false), findsOneWidget);
      expect(_visibility(tester), anyOf(isNull, 1.0));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a glass moved while its route is covered sits at its new place when the route shows again, with no spring', (tester) async {
    final left = ValueNotifier(0.0);
    addTearDown(left.dispose);
    await tester.pumpWidget(MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: left,
            builder: (context, x, _) => GlassEffectContainer(child: Padding(padding: EdgeInsets.only(left: x), child: _block(width: 80, height: 40))),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => const ColoredBox(color: Color(0xFF0000FF)),
    ));
    await tester.pump();
    await tester.pump();
    left.value = 100;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    navigator.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_onScreen(member).left, closeTo(100, 0.5), reason: 'frame $i after the pop');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a glass springing when its route is covered settles there, so the pop shows it at its new place', (tester) async {
    final left = ValueNotifier(0.0);
    addTearDown(left.dispose);
    await tester.pumpWidget(MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: left,
            builder: (context, x, _) => GlassEffectContainer(child: Padding(padding: EdgeInsets.only(left: x), child: _block(width: 80, height: 40))),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    left.value = 100;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_onScreen(member).left, inExclusiveRange(0, 100));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => const ColoredBox(color: Color(0xFF0000FF)),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    navigator.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_onScreen(member).left, closeTo(100, 0.5), reason: 'frame $i after the pop');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone glass with no Overlay appears at once', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(child: _Bare(children: (shown) => [const SizedBox(width: 10, height: 10), if (!shown) _block()])),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_BareState>(find.byType(_Bare)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(_visibility(tester), 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_visibility(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone glass with no Overlay disappears at once', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(child: _Bare(children: (shown) => [const SizedBox(width: 10, height: 10), if (shown) _block()])),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_BareState>(find.byType(_Bare)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inside withGlassAnimation, container glass leaving with its container ghosts in the nearest Overlay, as standalone glass does', (tester) async {
    late StateSetter set;
    var tab = 0;
    await tester.pumpWidget(MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(child: StatefulBuilder(builder: (context, setState) {
          set = setState;
          return tab == 0
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  GlassEffectContainer(child: _block(key: const ValueKey('c'), width: 100, height: 40, child: const ColoredBox(color: Color(0xFF00FF00)))),
                  _block(key: const ValueKey('s'), width: 100, height: 40, child: const ColoredBox(color: Color(0xFFFF0000))),
                ])
              : const SizedBox(width: 10, height: 10);
        })),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final container = tester.getRect(find.byKey(const ValueKey('c')));
    withGlassAnimation(GlassAnimation.bouncy, () => set(() => tab = 1));
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(find.descendant(of: find.byType(Overlay), matching: find.byType(RawImage)), findsNWidgets(2));
    expect(tester.getRect(find.byType(RawImage).first).center, container.center);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(RawImage), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a container glass removed after its page slid in leaves its ghost where the glass is on screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GlassTheme(data: const GlassThemeData(brightness: Brightness.dark), child: const SizedBox())));
    tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(builder: (context) => GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: Center(child: _Bare(children: (shown) => [GlassEffectContainer(child: SizedBox(width: 250, height: 88, child: shown ? _block(child: const ColoredBox(color: Color(0xFFFF0000))) : null))])),
    )));
    await tester.pump();
    await tester.pumpAndSettle();
    final glass = tester.getRect(find.byType(GlassEffect));
    tester.state<_BareState>(find.byType(_Bare)).toggle();
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    final ghost = tester.getRect(find.byType(RawImage));
    expect(ghost.center.dx, closeTo(glass.center.dx, 0.5));
    expect(ghost.center.dy, closeTo(glass.center.dy, 0.5));
  });

  testWidgets('a standalone glass removed after its page slid in leaves its ghost where the glass is on screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GlassTheme(data: const GlassThemeData(brightness: Brightness.dark), child: const SizedBox())));
    tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(builder: (context) => GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: Center(child: _Bare(children: (shown) => [SizedBox(width: 250, height: 88, child: shown ? _block(child: const ColoredBox(color: Color(0xFFFF0000))) : null)])),
    )));
    await tester.pump();
    await tester.pumpAndSettle();
    final glass = tester.getRect(find.byType(GlassEffect));
    tester.state<_BareState>(find.byType(_Bare)).toggle();
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    final ghost = tester.getRect(find.byType(RawImage));
    expect(ghost.center.dx, closeTo(glass.center.dx, 0.5));
    expect(ghost.center.dy, closeTo(glass.center.dy, 0.5));
  });

  test('a glass member box tracks its space with no platform switch, so the shader path refreshes the origin at compositing as FakeGlass does', () {
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    final box = RenderGlassMemberBox(GlassMember(coordinator));
    expect(box.alwaysNeedsCompositing, isTrue);
    coordinator.dispose();
  });

  testWidgets('a glass reads its appearance for the appear gain from its theme', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(home: GlassTheme(data: GlassThemeData(brightness: brightness), child: Center(child: _block()))));
      expect(_member(tester).dark, brightness == Brightness.dark);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a resting sibling is not notified while another glass of its container animates', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [
      SizedBox(width: 200, height: 100, child: Stack(children: [
        Positioned(left: 0, top: 0, child: _block(key: const ValueKey('resting'), width: 60, height: 40)),
        if (!shown) Positioned(left: 100, top: 0, child: _block(key: const ValueKey('new'), width: 60, height: 40)),
      ])),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final resting = _member(tester, find.byKey(const ValueKey('resting')));
    var notified = 0;
    resting.addListener(() => notified++);
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    final arriving = _member(tester, find.byKey(const ValueKey('new')));
    var frames = 0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (arriving.isMoving) frames++;
    }
    expect(frames, greaterThan(10));
    expect(notified, 0);
  });

  testWidgets('a snap to a detent right after a drag lands at once, and withGlassAnimation around the release springs it', (tester) async {
    var x = 0.0;
    late StateSetter drag;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        drag = setState;
        return Stack(children: [
          Positioned(left: x, top: 100, child: _block(key: const ValueKey('thumb'), width: 60, height: 40)),
        ]);
      }),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester);
    for (var i = 0; i < 6; i++) {
      drag(() => x += 15);
      await tester.pump(const Duration(milliseconds: 16));
    }
    drag(() => x = 200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_onScreen(member).left, closeTo(200, 0.5));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      drag(() => x -= 15);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_onScreen(member).left, closeTo(110, 0.5));
    withGlassAnimation(GlassAnimation.defaultSpring, () => drag(() => x = 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_onScreen(member).left, closeTo(110, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(0, 110));
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(0, 1e-6));
  });
}

class _Covered extends StatelessWidget {
  const _Covered({required this.shown, required this.container});

  final ValueNotifier<bool> shown;
  final bool container;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, on, _) {
              final slot = SizedBox(width: 250, height: 88, child: on ? _block(child: const ColoredBox(color: Color(0xFFFF0000))) : null);
              return container ? GlassEffectContainer(child: slot) : slot;
            },
          ),
        ),
      ),
    );
  }
}

class _Bare extends StatefulWidget {
  const _Bare({required this.children});

  final List<Widget> Function(bool shown) children;

  @override
  State<_Bare> createState() => _BareState();
}

class _BareState extends State<_Bare> {
  bool shown = true;

  void toggle() => setState(() => shown = !shown);

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: widget.children(shown));
}
