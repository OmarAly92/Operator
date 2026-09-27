import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

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

  for (final (brightness, expected) in const [(Brightness.light, Color(0xFFFFFFFF)), (Brightness.dark, Color(0xFF000000))]) {
    testWidgets('the fallback tints with the default edge tint (${brightness.name})', (tester) async {
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
      final box = tester.widget<ColoredBox>(
        find.descendant(of: find.byType(BackdropFilter), matching: find.byType(ColoredBox)),
      );
      expect(box.color.withValues(alpha: 1), expected);
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
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(BackdropFilter), matching: find.byType(ColoredBox)),
    );
    expect(box.color.withValues(alpha: 1), const Color(0xFFFAF7F2));
  });
}
