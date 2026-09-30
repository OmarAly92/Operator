import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

const _accent = Color(0xFF1ACB64);

Widget _host(Widget child, {Brightness brightness = Brightness.dark, Map<String, double> overrides = const {}}) => MaterialApp(
  home: GlassTheme(
    data: GlassThemeData(brightness: brightness, accent: _accent),
    child: GlassMaterialOverride(values: overrides, child: Center(child: child)),
  ),
);

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(width: 150, height: 44, child: Text('$count'));
}

void main() {
  isLocalTest = true;

  testWidgets('draws its own layer with the material resolved for its measured size', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 60))));
    await tester.pump();
    final layer = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer));
    final expected = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 60, brightness: Brightness.dark);
    final unmeasured = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 88, brightness: Brightness.dark);
    expect(layer.settings, expected.toSettings());
    expect(layer.settings, isNot(unmeasured.toSettings()));
  });

  testWidgets('re-resolves when the appearance flips', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88))));
    await tester.pump();
    final dark = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), brightness: Brightness.light));
    await tester.pump();
    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings, isNot(dark));
  });

  testWidgets('joins a container that holds the same glass', (tester) async {
    await tester.pumpWidget(_host(const GlassEffectContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [GlassEffect(child: SizedBox.square(dimension: 64)), GlassEffect(child: SizedBox.square(dimension: 64))],
      ),
    )));
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
  });

  testWidgets('interactive glass inside a regular container joins it', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(
      child: GlassEffect(glass: Glass.regular.interactive(), child: const SizedBox.square(dimension: 64)),
    )));
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
  });

  testWidgets('clear glass inside a regular container keeps its own layer', (tester) async {
    await tester.pumpWidget(_host(const GlassEffectContainer(
      child: GlassEffect(glass: Glass.clear, child: SizedBox.square(dimension: 64)),
    )));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
  });

  testWidgets('tinted glass inside a regular container keeps its own layer', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(
      child: GlassEffect(glass: Glass.regular.tint(_accent), child: const SizedBox.square(dimension: 64)),
    )));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), _accent);
  });

  testWidgets('identity glass draws no glass', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: SizedBox(width: 10, height: 10))));
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('switching to and from identity keeps the child state', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: _Counter())));
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;
    await tester.pumpWidget(_host(const GlassEffect(child: _Counter())));
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: _Counter())));
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
  });

  testWidgets('debug overrides reach the renderer', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), overrides: const {'frost': 17}));
    await tester.pump();
    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.blur, 17);
  });

  testWidgets('foreground is white in dark, black in light and white on tinted glass', (tester) async {
    Color? seen;
    Widget probe() => GlassForeground(child: Builder(builder: (context) {
      seen = DefaultTextStyle.of(context).style.color;
      return const SizedBox(width: 40, height: 20);
    }));
    await tester.pumpWidget(_host(GlassEffect(child: probe())));
    expect(seen, GlassForeground.dark);
    await tester.pumpWidget(_host(GlassEffect(child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.light);
    await tester.pumpWidget(_host(GlassEffect(glass: Glass.regular.tint(_accent), child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.tinted);
    await tester.pumpWidget(_host(GlassEffect(glass: Glass.clear.tint(_accent), child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.light);
  });

  testWidgets('dimming paints the 35% black layer in the glass shape', (tester) async {
    await tester.pumpWidget(_host(const GlassDimming(child: SizedBox(width: 250, height: 88))));
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(GlassDimming), matching: find.byType(DecoratedBox)));
    final decoration = box.decoration as ShapeDecoration;
    expect(decoration.color, const Color(0xFF000000).withValues(alpha: 0.35));
    expect(decoration.shape, const StadiumBorder());
  });
}
