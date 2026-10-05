import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

class _Toggle extends StatefulWidget {
  const _Toggle({required this.children, this.animation, this.row = false});

  final List<Widget> Function(bool shown) children;
  final GlassAnimation? animation;
  final bool row;

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
    final container = GlassEffectContainer(child: flex);
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
}
