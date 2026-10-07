import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

const List<String> _badges = ['star', 'heart', 'bolt'];

class _Morph extends StatefulWidget {
  const _Morph({this.badge = 56, this.transition, this.ids = true});

  final double badge;
  final GlassEffectTransition? transition;
  final bool ids;

  @override
  State<_Morph> createState() => _MorphState();
}

class _MorphState extends State<_Morph> {
  final GlassNamespace namespace = GlassNamespace();
  bool expanded = false;

  void toggle() => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => expanded = !expanded));

  Widget _glass(String name, double side) => GlassEffect(
    key: ValueKey(name),
    id: widget.ids ? GlassEffectID(name, namespace) : null,
    transition: name == 'toggle' ? null : widget.transition,
    child: SizedBox.square(dimension: side, child: const ColoredBox(color: Color(0xFFFF0000))),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(
          child: GlassEffectContainer(
            spacing: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (expanded)
                  for (final name in _badges) ...[_glass(name, widget.badge), const SizedBox(height: 16)],
                _glass('toggle', 56),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swap extends StatefulWidget {
  const _Swap();

  @override
  State<_Swap> createState() => _SwapState();
}

class _SwapState extends State<_Swap> {
  final GlassNamespace namespace = GlassNamespace();
  bool first = true;

  void swap() => setState(() => first = !first);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(
          alignment: Alignment.topLeft,
          child: GlassEffectContainer(
            child: SizedBox(
              width: 600,
              height: 400,
              child: Stack(
                children: [
                  if (first)
                    Positioned(
                      left: 20,
                      top: 20,
                      child: GlassEffect(
                        key: const ValueKey('a'),
                        id: GlassEffectID('x', namespace),
                        child: const SizedBox(width: 100, height: 40, child: ColoredBox(color: Color(0xFFFF0000))),
                      ),
                    )
                  else
                    Positioned(
                      left: 300,
                      top: 200,
                      child: GlassEffect(
                        key: const ValueKey('b'),
                        id: GlassEffectID('x', namespace),
                        child: const SizedBox(width: 200, height: 80, child: ColoredBox(color: Color(0xFF00FF00))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row();

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  final GlassNamespace namespace = GlassNamespace();
  bool shown = false;

  void toggle() => setState(() => shown = !shown);

  Widget _glass(String name) => GlassEffect(key: ValueKey(name), id: GlassEffectID(name, namespace), child: const SizedBox.square(dimension: 40));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(
          alignment: Alignment.topLeft,
          child: GlassEffectContainer(
            spacing: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _glass('a'),
                const SizedBox(width: 200),
                _glass('b'),
                if (shown) ...[const SizedBox(width: 16), _glass('c')],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

GlassMember _member(WidgetTester tester, String key) => tester
    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
    .member;

Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);

Rect _layout(WidgetTester tester, String key) => tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first);

GlassMotionCoordinator _coordinator(WidgetTester tester, String key) => _member(tester, key).coordinator;

Iterable<LiquidGlassLayer> _layers(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer));

void _expectRect(Rect actual, Rect expected, [double tolerance = 1e-6]) {
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.width, closeTo(expected.width, tolerance));
  expect(actual.height, closeTo(expected.height, tolerance));
}

double _gap(Rect a, Rect b) => (a.center - b.center).distance - a.shortestSide / 2 - b.shortestSide / 2;

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);
  tearDown(GlassAccessibility.debugReset);

  test('a glass id is equal to another with the same id in the same namespace, and to no other', () {
    final namespace = GlassNamespace();
    expect(GlassEffectID('a', namespace), GlassEffectID('a', namespace));
    expect(GlassEffectID('a', namespace).hashCode, GlassEffectID('a', namespace).hashCode);
    expect(GlassEffectID('a', namespace), isNot(GlassEffectID('b', namespace)));
    expect(GlassEffectID('a', namespace), isNot(GlassEffectID('a', GlassNamespace())));
    expect(GlassEffectID('a', namespace), isNot(GlassEffectUnion('a', namespace)));
  });

  test('a glass with an id and no transition morphs, and a glass without one materializes', () {
    final namespace = GlassNamespace();
    expect(const GlassEffect(child: SizedBox()).effectiveTransition, GlassEffectTransition.materialize);
    expect(GlassEffect(id: GlassEffectID('a', namespace), child: const SizedBox()).effectiveTransition, GlassEffectTransition.matchedGeometry);
    expect(
      GlassEffect(id: GlassEffectID('a', namespace), transition: GlassEffectTransition.materialize, child: const SizedBox()).effectiveTransition,
      GlassEffectTransition.materialize,
    );
    expect(const GlassEffect(transition: GlassEffectTransition.identity, child: SizedBox()).effectiveTransition, GlassEffectTransition.identity);
  });

  testWidgets('an appearing glass with an id starts on the glass it emerges from, at full visibility in the shared layer, and springs to its layout', (tester) async {
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    final before = _onScreen(_member(tester, 'toggle'));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    for (final name in _badges) {
      _expectRect(_onScreen(_member(tester, name)), before);
      expect(_member(tester, name).presence, GlassPresence.present);
    }
    _expectRect(_onScreen(_member(tester, 'toggle')), before);
    expect(_layers(tester), hasLength(1));
    await tester.pump(const Duration(milliseconds: 100));
    final heart = _onScreen(_member(tester, 'heart'));
    expect(heart.center.dy, lessThan(before.center.dy));
    expect(heart.center.dy, greaterThan(_layout(tester, 'heart').center.dy));
    expect(_layers(tester), hasLength(1));
    await tester.pumpAndSettle();
    for (final name in [..._badges, 'toggle']) {
      _expectRect(_onScreen(_member(tester, name)), _layout(tester, name));
    }
  });

  testWidgets('an appearing glass emerges from the nearest present glass', (tester) async {
    await tester.pumpWidget(const _Row());
    await tester.pump(const Duration(seconds: 1));
    final b = _onScreen(_member(tester, 'b'));
    tester.state<_RowState>(find.byType(_Row)).toggle();
    await tester.pump();
    _expectRect(_onScreen(_member(tester, 'c')), b);
    await tester.pumpAndSettle();
    _expectRect(_onScreen(_member(tester, 'c')), _layout(tester, 'c'));
  });

  testWidgets('normal motion starts an appearing glass at the size of its source, Reduce Motion at its own size', (tester) async {
    await tester.pumpWidget(const _Morph(badge: 40));
    await tester.pump(const Duration(seconds: 1));
    final before = _onScreen(_member(tester, 'toggle'));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    _expectRect(_onScreen(_member(tester, 'heart')), before);
    await tester.pumpAndSettle();
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pumpAndSettle();
    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
    await tester.pump();
    final collapsed = _onScreen(_member(tester, 'toggle'));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    _expectRect(_onScreen(_member(tester, 'heart')), Rect.fromCenter(center: collapsed.center, width: 40, height: 40));
  });

  testWidgets('a morphing glass keeps its content blurred until it separates from the other glass of the morph, then sharpens in one frame', (tester) async {
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    for (final name in ['toggle']) {
      expect(_member(tester, name).contentBlurred.value, isFalse);
    }
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    final names = [..._badges, 'toggle'];
    for (final name in names) {
      expect(_member(tester, name).contentBlurred.value, isTrue, reason: name);
      expect(_member(tester, name).contentOpacity.value, 1, reason: name);
    }
    final sharpened = <String, int>{};
    for (var frame = 1; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      final rects = {for (final name in names) name: _onScreen(_member(tester, name))};
      for (final name in names) {
        final blurred = _member(tester, name).contentBlurred.value;
        if (sharpened.containsKey(name)) {
          expect(blurred, isFalse, reason: '$name blurred again');
          continue;
        }
        if (blurred) continue;
        sharpened[name] = frame;
        for (final other in names.where((other) => other != name)) {
          expect(_gap(rects[name]!, rects[other]!), greaterThanOrEqualTo(10 - 1e-6), reason: '$name sharpened while touching $other');
        }
      }
    }
    expect(sharpened.keys.toSet(), names.toSet());
  });

  testWidgets('under Reduce Motion an appearing glass fades its content in sharp', (tester) async {
    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    expect(_member(tester, 'heart').contentOpacity.value, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_member(tester, 'heart').contentOpacity.value, inExclusiveRange(0, 1));
    for (final name in [..._badges, 'toggle']) {
      expect(_member(tester, name).contentBlurred.value, isFalse);
    }
    await tester.pumpAndSettle();
    expect(_member(tester, 'heart').contentOpacity.value, 1);
  });

  testWidgets('a removed glass within spacing of a remaining glass sinks into it in the shared layer; a farther one dematerializes in place', (tester) async {
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_MorphState>(find.byType(_Morph));
    state.toggle();
    await tester.pumpAndSettle();
    final star = _onScreen(_member(tester, 'star'));
    final heart = _onScreen(_member(tester, 'heart'));
    final coordinator = _coordinator(tester, 'toggle');
    state.toggle();
    await tester.pump();
    expect(coordinator.ghosts, hasLength(3));
    await tester.pump(const Duration(milliseconds: 16));
    final target = _layout(tester, 'toggle').center;
    final kinds = {for (final ghost in coordinator.ghosts) ghost.rect.center.dy.round(): ghost.kind};
    expect(kinds[star.center.dy.round()], GlassGhostKind.dematerialize);
    expect(kinds[heart.center.dy.round()], GlassGhostKind.sink);
    expect(coordinator.ghosts.where((ghost) => ghost.kind == GlassGhostKind.sink), hasLength(2));
    expect(_layers(tester), hasLength(2));
    final sinking = coordinator.ghosts.firstWhere((ghost) => ghost.rect.center.dy.round() == heart.center.dy.round());
    await tester.pump(const Duration(milliseconds: 60));
    final now = sinking.current;
    expect((now.center - target).distance, lessThan((heart.center - target).distance));
    expect(now.width, lessThan(heart.width));
    expect(sinking.member.visibility.value, 1);
    final dematerializing = coordinator.ghosts.firstWhere((ghost) => ghost.kind == GlassGhostKind.dematerialize);
    _expectRect(dematerializing.current, star);
    expect(dematerializing.member.visibility.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(coordinator.ghosts, isEmpty);
    expect(_layers(tester), hasLength(1));
  });

  testWidgets('under Reduce Motion a sinking glass slides into its target at full size', (tester) async {
    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_MorphState>(find.byType(_Morph));
    state.toggle();
    await tester.pumpAndSettle();
    final heart = _onScreen(_member(tester, 'heart'));
    final coordinator = _coordinator(tester, 'toggle');
    state.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final target = _layout(tester, 'toggle').center;
    final sinking = coordinator.ghosts.firstWhere((ghost) => ghost.rect.center.dy.round() == heart.center.dy.round());
    expect(sinking.kind, GlassGhostKind.sink);
    await tester.pump(const Duration(milliseconds: 100));
    expect((sinking.current.center - target).distance, lessThan((heart.center - target).distance));
    expect(sinking.current.size, heart.size);
    for (final ghost in coordinator.ghosts) {
      expect(ghost.blurred, isFalse);
    }
    await tester.pumpAndSettle();
    expect(coordinator.ghosts, isEmpty);
  });

  testWidgets('removed glass blurs its content at once and the glass it sinks into stays blurred until it has sunk', (tester) async {
    await tester.pumpWidget(const _Morph());
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_MorphState>(find.byType(_Morph));
    state.toggle();
    await tester.pumpAndSettle();
    final coordinator = _coordinator(tester, 'toggle');
    state.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    for (final ghost in coordinator.ghosts) {
      expect(ghost.blurred, isTrue);
    }
    expect(_member(tester, 'toggle').contentBlurred.value, isTrue);
    while (coordinator.ghosts.any((ghost) => ghost.kind == GlassGhostKind.sink)) {
      expect(_member(tester, 'toggle').contentBlurred.value, isTrue);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pump(const Duration(milliseconds: 8));
    expect(_member(tester, 'toggle').contentBlurred.value, isFalse);
  });

  testWidgets('a glass with an id and an explicit materialize transition still materializes', (tester) async {
    await tester.pumpWidget(const _Morph(transition: GlassEffectTransition.materialize));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    expect(_member(tester, 'heart').presence, GlassPresence.appearing);
    expect(_layers(tester).length, greaterThan(1));
  });

  testWidgets('glass without an id keeps materializing', (tester) async {
    await tester.pumpWidget(const _Morph(ids: false));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_MorphState>(find.byType(_Morph)).toggle();
    await tester.pump();
    expect(_member(tester, 'heart').presence, GlassPresence.appearing);
  });

  testWidgets('a glass removed and another inserted with the same id in the same frame draw as one glass that springs from the old rect to the new', (tester) async {
    await tester.pumpWidget(const _Swap());
    await tester.pump(const Duration(seconds: 1));
    final old = _onScreen(_member(tester, 'a'));
    final coordinator = _coordinator(tester, 'a');
    tester.state<_SwapState>(find.byType(_Swap)).swap();
    await tester.pump();
    final member = _member(tester, 'b');
    _expectRect(_onScreen(member), old);
    expect(member.presence, GlassPresence.present);
    expect(coordinator.ghosts, hasLength(1));
    expect(coordinator.ghosts.single.kind, GlassGhostKind.content);
    expect(_layers(tester), hasLength(1));
    expect(member.contentOpacity.value, 0);
    _expectRect(coordinator.ghosts.single.current, old);
    await tester.pump(const Duration(milliseconds: 120));
    final mid = _onScreen(member);
    expect(mid.left, inExclusiveRange(old.left, 300));
    expect(mid.width, inExclusiveRange(100, 200));
    expect(member.contentOpacity.value, inExclusiveRange(0, 1));
    _expectRect(coordinator.ghosts.single.current, mid);
    expect(coordinator.ghosts.single.opacity.value, closeTo(1 - member.contentOpacity.value, 1e-9));
    await tester.pumpAndSettle();
    _expectRect(_onScreen(member), _layout(tester, 'b'));
    expect(member.contentOpacity.value, 1);
    expect(coordinator.ghosts, isEmpty);
  });
}
