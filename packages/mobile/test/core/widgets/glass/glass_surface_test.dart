import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

const _accent = Color(0xFF1ACB64);

Widget _host(Brightness brightness, Widget child) => MaterialApp(
  home: GlassTheme(
    data: GlassThemeData(brightness: brightness, accent: _accent),
    child: Center(child: child),
  ),
);

const _surface = GlassScope(
  variant: GlassVariant.regular,
  size: 44,
  child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 120, height: 44, child: Text('glass'))),
);

void main() {
  testWidgets('renders its child inside a glass layer', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, _surface));
    expect(find.text('glass'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching appearance updates the layer material without remounting', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, _surface));
    final before = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    final element = tester.element(find.byType(LiquidGlassLayer));
    await tester.pumpWidget(_host(Brightness.dark, _surface));
    final after = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    expect(after, isNot(before));
    expect(tester.element(find.byType(LiquidGlassLayer)), same(element));
  });

  testWidgets('prominent glass keeps its own tinted layer inside a regular scope', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.prominent, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), _accent);
  });

  testWidgets('clear glass keeps its own layer with the clear material', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.clear, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    final clear = GlassMaterial.resolve(glass: Glass.clear, shorterSide: 44, brightness: Brightness.light);
    expect(inner.settings.toneBlack, clear['toneBlack']);
    expect(inner.settings.toneWhite, clear['toneWhite']);
  });

  testWidgets('a rounded rect uses a plain rounded rectangle at its radius, so it can morph from a capsule', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassSurface(kind: GlassShapeKind.roundedRect, size: 48, radius: 26, child: SizedBox(width: 200, height: 90)),
    ));
    final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    expect(glass.shape, isA<LiquidRoundedRectangle>());
    expect((glass.shape as LiquidRoundedRectangle).borderRadius, 26);
    expect(tester.takeException(), isNull);
  });
}
