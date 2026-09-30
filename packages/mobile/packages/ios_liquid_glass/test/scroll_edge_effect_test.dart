import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/scroll_edge/scroll_edge_effect.dart';

void main() {
  testWidgets('does not intercept taps on content below it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: Stack(
            children: [
              Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.orange))),
              const Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120)),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 40));
    expect(taps, 1);
    expect(tester.getSize(find.byType(ScrollEdgeEffect)).height, 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the fallback with no exception once settled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: const Stack(
            children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden edge effect draws no blur at all', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: const Stack(
            children: [
              Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120, visibility: 0)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.getSize(find.byType(ScrollEdgeEffect)).height, 120);
  });

  ScrollEdgeTintPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ScrollEdgeTintPainter)).painter! as ScrollEdgeTintPainter;

  for (final (brightness, expected) in const [(Brightness.light, Color(0xFFFFFFFF)), (Brightness.dark, Color(0xFF000000))]) {
    testWidgets('the band tints with the default edge tint (${brightness.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GlassTheme(
            data: GlassThemeData(brightness: brightness),
            child: const Stack(
              children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
            ),
          ),
        ),
      );
      expect(painterOf(tester).tint, expected);
    });
  }

  testWidgets('the theme edge tint overrides the default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassTheme(
          data: GlassThemeData(brightness: Brightness.light, scrollEdgeTint: Color(0xFFFAF7F2)),
          child: Stack(
            children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
          ),
        ),
      ),
    );
    expect(painterOf(tester).tint, const Color(0xFFFAF7F2));
  });

  test('a hard band is one true Gaussian over the whole band', () {
    final levels = ScrollEdgeEffect.levels(blur: 5, knee: 0, capBlur: 0, capExtent: 0);
    expect(levels, hasLength(1));
    expect(levels.single.sigma, 5);
    expect(levels.single.uniform, isTrue);
    expect(levels.single.weightAt(10, 120, 0, 0), 1);
    expect(levels.single.weightAt(130, 120, 0, 0), 0);
  });

  test('a soft band stacks Gaussians whose combined sigma grows to the full blur at the edge', () {
    final levels = ScrollEdgeEffect.levels(blur: 8, knee: 0.4, capBlur: 0, capExtent: 0);
    expect(levels, hasLength(ScrollEdgeEffect.softLevels));
    final combined = levels.fold<double>(0, (sum, level) => sum + level.sigma * level.sigma);
    expect(combined, closeTo(64, 1e-9));
    for (final level in levels) {
      expect(level.weightAt(0, 120, 0.4, 0), 1);
      expect(level.weightAt(120, 120, 0.4, 0), 0);
    }
    expect(levels.first.weightAt(100, 120, 0.4, 0), greaterThan(levels.last.weightAt(100, 120, 0.4, 0)));
  });

  test('the blur ramp has its own knee and reach, and a hard band ignores them', () {
    expect(ScrollEdgeMaterial.defaults['blurKnee'], ScrollEdgeMaterial.defaults['knee']);
    expect(ScrollEdgeMaterial.defaults['blurReach'], 1);
    final soft = ScrollEdgeEffect.levels(blur: 4, knee: 0.3, capBlur: 0, capExtent: 0);
    expect(soft.first.weightAt(100, 120 * 0.8, 0.3, 0), 0);
    expect(soft.first.weightAt(100, 120, 0.3, 0), greaterThan(0));
  });

  testWidgets('a hard band stays one uniform blur whatever its blur knee', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassTheme(
          data: GlassThemeData(brightness: Brightness.dark),
          child: GlassMaterialOverride(
            values: {'edge.blurKnee': 0.3, 'edge.blurReach': 0.5},
            child: Stack(
              children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120, style: ScrollEdgeStyle.hard))],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });

  test('the cap level only covers the cap', () {
    final levels = ScrollEdgeEffect.levels(blur: 5, knee: 0, capBlur: 3, capExtent: 60);
    final cap = levels.last;
    expect(cap.cap, isTrue);
    expect(cap.weightAt(10, 120, 0, 60), 1);
    expect(cap.weightAt(70, 120, 0, 60), 0);
  });

  test('the tint follows the band weight and the cap, and draws the line only when asked', () {
    const painter = ScrollEdgeTintPainter(
      fromTop: true, tint: Color(0xFF000000), dim: 0.6, knee: 0, cap: 0.9, capExtent: 50, line: 0.3, lineShade: 0.5,
    );
    expect(painter.alphaAt(10, 100), closeTo(0.9, 1e-9));
    expect(painter.alphaAt(80, 100), closeTo(0.6, 1e-9));
    expect(painter.alphaAt(100, 100), 0);
  });
}
