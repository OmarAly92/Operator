import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/motion/glass_press.dart';
import 'package:ios_liquid_glass/src/motion/glass_press_widgets.dart';
import 'package:ios_liquid_glass/src/motion/ios27_press.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

const Duration _frame = Duration(milliseconds: 16);

Duration _seconds(double value) => Duration(microseconds: (value * 1000000).round());

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Center(child: child),
  ),
);

Widget _block({Glass? glass, double width = 250, double height = 88, Key? key, Widget? child}) => GlassEffect(
  key: key,
  glass: glass ?? Glass.regular.interactive(),
  child: SizedBox(width: width, height: height, child: child),
);

List<GlassMember> _members(WidgetTester tester) =>
    tester.renderObjectList<RenderGlassMemberBox>(find.byType(GlassMemberBox)).map((box) => box.member).toList();

GlassMember _member(WidgetTester tester) => _members(tester).single;

Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _hold(WidgetTester tester, Duration duration) async {
  final end = tester.binding.clock.now().add(duration);
  while (tester.binding.clock.now().isBefore(end)) {
    await tester.pump(_frame);
  }
}

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  test('the size law grows small glass by the cap and larger glass by its height and width, portrait or landscape, the same factor on both axes', () {
    expect(GlassPress.widthGrowth(const Size(250, 44)), ios27PressGrowthCap);
    expect(GlassPress.widthGrowth(const Size(44, 44)), ios27PressGrowthCap);
    double law(double width, double height) => ios27PressGrowthAt100 * math.pow(100 / height, ios27PressGrowthPower) * math.pow(100 / width, ios27PressGrowthWidthPower);
    expect(GlassPress.widthGrowth(const Size(250, 88)), closeTo(math.min(ios27PressGrowthCap, law(250, 88)), 1e-9));
    expect(GlassPress.widthGrowth(const Size(360, 200)), closeTo(law(360, 200), 1e-9));
    expect(GlassPress.widthGrowth(const Size(120, 250)), closeTo(law(120, 250), 1e-9));
    expect(GlassPress.widthGrowth(const Size(360, 100)), closeTo(math.min(ios27PressGrowthCap, law(360, 100)), 1e-9));
    expect(GlassPress.widthGrowth(const Size(0, 88)), 0);
    expect(GlassPress.scaleFor(const Size(250, 88), 1), closeTo(1 + math.min(ios27PressGrowthCap, law(250, 88)) / 250, 1e-9));
    expect(GlassPress.scaleFor(const Size(250, 88), 0), 1);
  });

  test('the glow table is held at its ends', () {
    final (hold, swell) = GlassPress.glowFor(Size(ios27PressGlowAreas.first, 1));
    expect(hold, closeTo(ios27PressGlowHoldLuma.first / 255, 1e-9));
    expect(swell, closeTo(ios27PressGlowSwellLuma.first / 255, 1e-9));
    final (big, _) = GlassPress.glowFor(Size(ios27PressGlowAreas.last * 2, 1));
    expect(big, closeTo(ios27PressGlowHoldLuma.last / 255, 1e-9));
  });

  test('the glow table is interpolated in log area between its stops', () {
    const areas = ios27PressGlowAreas;
    for (var i = 1; i < areas.length; i++) {
      final mid = math.sqrt(areas[i - 1] * areas[i]);
      final (hold, swell) = GlassPress.glowFor(Size(mid, 1));
      expect(hold, closeTo((ios27PressGlowHoldLuma[i - 1] + ios27PressGlowHoldLuma[i]) / 2 / 255, 1e-9));
      expect(swell, closeTo((ios27PressGlowSwellLuma[i - 1] + ios27PressGlowSwellLuma[i]) / 2 / 255, 1e-9));
    }
  });

  test('a second press restarts the swell from where it is, not from zero', () {
    final press = GlassPress();
    press.down(Offset.zero, reduceMotion: false, cut: 0.7, now: Duration.zero);
    for (var ms = 16; ms <= 120; ms += 16) {
      press.sample(Duration(milliseconds: ms));
    }
    final before = press.swell;
    expect(before, greaterThan(0));
    press.down(Offset.zero, reduceMotion: false, cut: 0.7, now: const Duration(milliseconds: 120));
    expect(press.swell, closeTo(before, 1e-9));
  });

  testWidgets('the press target passes a tap outside its shape to its child and presses only for a tap on the shape', (tester) async {
    final coordinator = GlassMotionCoordinator(vsync: tester);
    final member = GlassMember(coordinator);
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassPressTarget(
            member: member,
            shape: const LiquidOval(),
            child: SizedBox(width: 44, height: 44, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++)),
          ),
        ),
      ),
    );
    final topLeft = tester.getTopLeft(find.byType(GlassPressTarget));
    final corner = await tester.startGesture(topLeft + const Offset(2, 2));
    await corner.up();
    expect(taps, 1);
    expect(member.press.isPressed, isFalse);
    final centre = await tester.startGesture(topLeft + const Offset(22, 22));
    expect(member.press.isPressed, isTrue);
    await centre.up();
    expect(taps, 2);
    coordinator.dispose();
  });

  testWidgets('the held light is additive over the backdrop, also under the content fade at rest', (tester) async {
    final coordinator = GlassMotionCoordinator(vsync: tester);
    final member = GlassMember(coordinator);
    member.press.down(const Offset(125, 44), reduceMotion: false, cut: 1, now: Duration.zero);
    final boundary = GlobalKey();
    Future<int> grey(Widget glow) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(color: const Color(0xFF808080), child: SizedBox(width: 250, height: 88, child: glow)),
            ),
          ),
        ),
      );
      return (await tester.runAsync(() async {
        final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundary));
        final image = await render.toImage();
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final offset = (4 * image.width + 4) * 4;
        return data.getUint8(offset);
      }))!;
    }
    final (holdAlpha, _) = GlassPress.glowFor(const Size(250, 88));
    final expected = 128 + 255 * holdAlpha;
    final bare = await grey(CustomPaint(painter: GlassPressGlow(member)));
    final faded = await grey(FadeTransition(opacity: member.contentOpacity, child: CustomPaint(painter: GlassPressGlow(member))));
    expect(bare, closeTo(expected, 1.5));
    expect(faded, closeTo(expected, 1.5));
    coordinator.dispose();
  });

  testWidgets('a press lights the glass at once and grows it after the growth delay, uniformly, to the size law', (tester) async {
    await _show(tester, _app(_block()));
    final member = _member(tester);
    final rest = member.drawn!;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await tester.pump(_frame);
    expect(member.press.hold, 1);
    expect(member.drawn, rest);
    await tester.pump(_frame);
    expect(member.press.swell, greaterThan(0));
    await tester.pump(_frame);
    expect(ios27PressGrowthDelay, greaterThan(0.048));
    expect(member.drawn, rest);
    await _hold(tester, const Duration(seconds: 1));
    final grown = member.drawn!;
    final scale = GlassPress.scaleFor(const Size(250, 88), 1);
    expect(grown.width, closeTo(250 * scale, 0.05));
    expect(grown.height, closeTo(88 * scale, 0.05));
    expect(grown.center, rest.center);
    await gesture.up();
    await _hold(tester, const Duration(seconds: 2));
    expect(member.drawn, rest);
  });

  testWidgets('on release the glow stays until the cut and drops to nothing in one frame', (tester) async {
    await _show(tester, _app(_block()));
    final member = _member(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await _hold(tester, const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(_frame);
    await _hold(tester, _seconds(GlassPress.cutFor(const Size(250, 88), reduceMotion: false)) - const Duration(milliseconds: 40));
    expect(member.press.hold, 1);
    await _hold(tester, const Duration(milliseconds: 60));
    expect(member.press.hold, 0);
    expect(member.press.swell, 0);
  });

  testWidgets('under Reduce Motion the glass lights and never grows, and the cut comes at the Reduce Motion time', (tester) async {
    await _show(tester, _app(_block(), reduceMotion: true));
    final member = _member(tester);
    final rest = member.drawn!;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await _hold(tester, const Duration(seconds: 1));
    expect(member.press.hold, 1);
    expect(member.drawn, rest);
    await gesture.up();
    await tester.pump(_frame);
    await _hold(tester, _seconds(ios27PressReduceMotionGlowCut) - const Duration(milliseconds: 40));
    expect(member.press.hold, 1);
    await _hold(tester, const Duration(milliseconds: 60));
    expect(member.press.hold, 0);
  });

  testWidgets('a button inside interactive glass keeps its tap, and the glass reacts too', (tester) async {
    var taps = 0;
    await _show(tester, _app(_block(child: Center(child: TextButton(onPressed: () => taps++, child: const Text('Go'))))));
    final member = _member(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump(_frame);
    expect(member.press.isPressed, isTrue);
    await gesture.up();
    await tester.pump(_frame);
    expect(taps, 1);
    expect(member.press.isPressed, isFalse);
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('with nested interactive glass only the innermost reacts', (tester) async {
    await _show(tester, _app(_block(width: 300, height: 200, child: Center(child: _block(width: 120, height: 60)))));
    final members = _members(tester);
    expect(members, hasLength(2));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect).first));
    await tester.pump(_frame);
    final pressed = members.where((m) => m.press.isPressed).toList();
    expect(pressed, hasLength(1));
    expect(pressed.single.drawn!.width, lessThan(200));
    await gesture.up();
    await tester.pump(_frame);
    expect(RenderGlassPressTarget.claimedPointers, isEmpty);
    final outer = await tester.startGesture(tester.getTopLeft(find.byType(GlassEffect).first) + const Offset(150, 20));
    await tester.pump(_frame);
    expect(members.where((m) => m.press.isPressed).single.drawn!.width, greaterThan(200));
    await outer.up();
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('a touch outside the shape does not press, and plain glass never presses', (tester) async {
    await _show(tester, _app(Column(mainAxisSize: MainAxisSize.min, children: [_block(), _block(glass: Glass.regular)])));
    final members = _members(tester);
    final corner = await tester.startGesture(tester.getTopLeft(find.byType(GlassEffect).first) + const Offset(3, 3));
    await tester.pump(_frame);
    expect(members.any((m) => m.press.isPressed), isFalse);
    await corner.up();
    final plain = await tester.startGesture(tester.getCenter(find.byType(GlassEffect).last));
    await tester.pump(_frame);
    expect(members.any((m) => m.press.isPressed), isFalse);
    await plain.up();
    await tester.pump(_frame);
  });

  testWidgets('a drag that leaves the glass keeps the press until the finger lifts, as native does', (tester) async {
    await _show(tester, _app(_block()));
    final member = _member(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await tester.pump(_frame);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(_frame);
    }
    expect(member.press.isPressed, isTrue);
    await gesture.up();
    await tester.pump(_frame);
    expect(member.press.isPressed, isFalse);
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('a scroll that takes over releases the press', (tester) async {
    await _show(tester, _app(SizedBox(
      height: 400,
      child: ListView(children: [const SizedBox(height: 100), _block(), const SizedBox(height: 900)]),
    )));
    final member = _member(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await tester.pump(_frame);
    expect(member.press.isPressed, isTrue);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(_frame);
    }
    expect(member.press.isPressed, isFalse);
    await gesture.up();
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('a press that starts while the glass appears keeps going after the appear settles', (tester) async {
    await tester.pumpWidget(_app(_block()));
    await tester.pump(_frame);
    final member = _member(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await tester.pump(_frame);
    expect(member.press.isPressed, isTrue);
    await _hold(tester, const Duration(seconds: 2));
    expect(member.press.isPressed, isTrue);
    await gesture.up();
    await _hold(tester, const Duration(seconds: 2));
    expect(member.press.isPressed, isFalse);
  });

  testWidgets('a standalone glass removed while pressed goes without an error and leaves no ticker running', (tester) async {
    await _show(tester, _app(_block()));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await _hold(tester, const Duration(milliseconds: 300));
    await tester.pumpWidget(_app(const SizedBox()));
    await _hold(tester, const Duration(seconds: 2));
    await gesture.up();
    await tester.pump(_frame);
    expect(tester.takeException(), isNull);
    expect(RenderGlassPressTarget.claimedPointers, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a Reduce Motion switch during a press applies from the next press', (tester) async {
    await _show(tester, _app(_block()));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await _hold(tester, const Duration(milliseconds: 100));
    await tester.pumpWidget(_app(_block(), reduceMotion: true));
    await _hold(tester, const Duration(milliseconds: 900));
    expect(_member(tester).contentScale, greaterThan(1));
    await gesture.up();
    await _hold(tester, const Duration(seconds: 2));
    final next = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
    await _hold(tester, const Duration(seconds: 1));
    expect(_member(tester).press.isPressed, isTrue);
    expect(_member(tester).contentScale, 1);
    await next.up();
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('a container glass removed while grown leaves the container with its other glass and no error', (tester) async {
    Widget pair(bool both) => _app(GlassEffectContainer(
      child: Row(mainAxisSize: MainAxisSize.min, children: [if (both) _block(width: 120), const SizedBox(width: 40), _block(width: 120)]),
    ));
    await _show(tester, pair(true));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect).first));
    await _hold(tester, const Duration(seconds: 1));
    expect(_members(tester).first.contentScale, greaterThan(1));
    await tester.pumpWidget(pair(false));
    await _hold(tester, const Duration(seconds: 2));
    await gesture.up();
    await _hold(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(_members(tester), hasLength(1));
    expect(_members(tester).single.contentScale, 1);
  });

  testWidgets('a second finger on a pressed glass is ignored and the first finger releases it', (tester) async {
    await _show(tester, _app(_block()));
    final member = _member(tester);
    final centre = tester.getCenter(find.byType(GlassEffect));
    final first = await tester.startGesture(centre);
    await tester.pump(_frame);
    final second = await tester.startGesture(centre + const Offset(40, 0), pointer: 7);
    await tester.pump(_frame);
    expect(RenderGlassPressTarget.claimedPointers, hasLength(1));
    await first.up();
    await tester.pump(_frame);
    expect(member.press.isPressed, isFalse);
    await second.up();
    await tester.pump(_frame);
    expect(RenderGlassPressTarget.claimedPointers, isEmpty);
    await _hold(tester, const Duration(seconds: 2));
  });

  testWidgets('the press keeps its own springs inside withGlassAnimation', (tester) async {
    Future<double> widthAfter(bool wrapped) async {
      await _show(tester, _app(_block(key: UniqueKey())));
      if (wrapped) withGlassAnimation(GlassAnimation.bouncy, () {});
      final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassEffect)));
      await _hold(tester, const Duration(milliseconds: 200));
      final width = _member(tester).drawn!.width;
      await gesture.up();
      await _hold(tester, const Duration(seconds: 2));
      return width;
    }

    final plain = await widthAfter(false);
    final wrapped = await widthAfter(true);
    expect(plain, greaterThan(250));
    expect(wrapped, closeTo(plain, 1e-6));
  });
}
