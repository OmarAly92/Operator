import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

class _Spaced extends StatefulWidget {
  const _Spaced({required this.spacing, this.scope, this.reduceMotion = false, this.ticking = true});

  final double spacing;
  final GlassAnimation? scope;
  final bool reduceMotion;
  final bool ticking;

  @override
  State<_Spaced> createState() => _SpacedState();
}

class _SpacedState extends State<_Spaced> {
  late double spacing = widget.spacing;

  void set(double value) => setState(() => spacing = value);

  @override
  Widget build(BuildContext context) {
    Widget child = GlassEffectContainer(
      spacing: spacing,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassEffect(shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
          GlassEffect(shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
        ],
      ),
    );
    final scope = widget.scope;
    if (scope != null) child = GlassAnimationScope(animation: scope, child: child);
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: widget.reduceMotion),
        child: TickerMode(enabled: widget.ticking, child: Center(child: child)),
      ),
    );
  }
}

double _spacing(WidgetTester tester) {
  final group = tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup));
  return group.blendMotion?.value ?? group.blend;
}

_SpacedState _state(WidgetTester tester) => tester.state<_SpacedState>(find.byType(_Spaced));

const Duration _frame = Duration(milliseconds: 16);

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  test('a container blends at native default spacing, 8 pt', () {
    expect(const GlassEffectContainer(child: SizedBox()).spacing, 8);
  });

  testWidgets('a container draws its glass at the spacing it is given, from the first frame', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    expect(_spacing(tester), 40);
    await tester.pumpWidget(MaterialApp(home: Center(child: GlassEffectContainer(child: const GlassEffect(child: SizedBox.square(dimension: 80))))));
    expect(_spacing(tester), 8);
  });

  testWidgets('a spacing change springs with the default spring, on the container ticker, with no rebuild', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    _state(tester).set(0);
    await tester.pump();
    expect(_spacing(tester), 40);
    final builds = tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup));
    final expected = GlassAnimation.defaultSpring.simulate(40, 0, 0);
    var elapsed = 0;
    for (final step in [50, 50, 100, 200]) {
      await tester.pump(Duration(milliseconds: step));
      elapsed += step;
      expect(_spacing(tester), closeTo(expected.x(elapsed / 1000), 1e-9), reason: '$elapsed ms');
    }
    expect(identical(tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup)), builds), isTrue);
    await tester.pumpAndSettle();
    expect(_spacing(tester), 0);
  });

  testWidgets('withGlassAnimation picks the spacing animation first, then GlassAnimationScope, then the default', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40, scope: GlassAnimation.bouncy));
    withGlassAnimation(GlassAnimation.snappy, () => _state(tester).set(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_spacing(tester), closeTo(GlassAnimation.snappy.simulate(40, 0, 0).x(0.12), 1e-9));
    await tester.pumpAndSettle();
    _state(tester).set(40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_spacing(tester), closeTo(GlassAnimation.bouncy.simulate(0, 40, 0).x(0.12), 1e-9));
    await tester.pumpAndSettle();
  });

  testWidgets('GlassAnimation.none, from withGlassAnimation or a scope, changes the spacing at once', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    withGlassAnimation(GlassAnimation.none, () => _state(tester).set(0));
    await tester.pump();
    expect(_spacing(tester), 0);
    await tester.pumpWidget(const _Spaced(spacing: 0, scope: GlassAnimation.none));
    _state(tester).set(24);
    await tester.pump();
    expect(_spacing(tester), 24);
  });

  testWidgets('a spacing retargeted mid-flight keeps its value and velocity', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    _state(tester).set(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final first = GlassAnimation.defaultSpring.simulate(40, 0, 0);
    _state(tester).set(20);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_spacing(tester), closeTo(first.x(0.15), 1e-9));
    final second = GlassAnimation.defaultSpring.simulate(first.x(0.15), 20, first.dx(0.15));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_spacing(tester), closeTo(second.x(0.08), 1e-9));
    await tester.pumpAndSettle();
    expect(_spacing(tester), 20);
  });

  testWidgets('a spacing the app changes on consecutive frames follows its value, and a single change after springs again', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    _state(tester).set(38);
    await tester.pump(_frame);
    expect(_spacing(tester), 40);
    for (var value = 36.0; value >= 20; value -= 2) {
      _state(tester).set(value);
      await tester.pump(_frame);
      expect(_spacing(tester), value);
    }
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 100));
    _state(tester).set(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_spacing(tester), closeTo(GlassAnimation.defaultSpring.simulate(20, 0, 0).x(0.1), 1e-9));
    await tester.pumpAndSettle();
  });

  testWidgets('inside withGlassAnimation, spacing changes on consecutive frames all spring', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40));
    withGlassAnimation(GlassAnimation.smooth, () => _state(tester).set(30));
    await tester.pump(_frame);
    withGlassAnimation(GlassAnimation.smooth, () => _state(tester).set(20));
    await tester.pump(_frame);
    expect(_spacing(tester), greaterThan(30));
    await tester.pumpAndSettle();
    expect(_spacing(tester), 20);
  });

  testWidgets('under Reduce Motion the spacing springs as the drawn rects do', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40, reduceMotion: true));
    _state(tester).set(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_spacing(tester), closeTo(GlassAnimation.defaultSpring.simulate(40, 0, 0).x(0.1), 1e-9));
    await tester.pumpAndSettle();
  });

  testWidgets('a container whose ticker is muted changes its spacing at once', (tester) async {
    await tester.pumpWidget(const _Spaced(spacing: 40, ticking: false));
    _state(tester).set(0);
    await tester.pump();
    expect(_spacing(tester), 0);
  });
}
