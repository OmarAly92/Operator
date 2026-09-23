import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

Widget _host(AppSkin skin, Widget child, {bool highContrast = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: SkinScope(skin: skin, child: Center(child: child)),
      ),
    );

const _surface = GlassScope(
  variant: GlassVariant.regular,
  size: 44,
  child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 120, height: 44, child: Text('glass'))),
);

void main() {
  testWidgets('renders its child inside a glass layer', (tester) async {
    await tester.pumpWidget(_host(const LightSkin(), _surface));
    expect(find.text('glass'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching skin updates the layer tint without remounting', (tester) async {
    await tester.pumpWidget(_host(const LightSkin(), _surface));
    final before = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.glassColor;
    final element = tester.element(find.byType(LiquidGlassLayer));
    await tester.pumpWidget(_host(const DarkSkin(), _surface));
    final after = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.glassColor;
    expect(after, isNot(before));
    expect(tester.element(find.byType(LiquidGlassLayer)), same(element));
  });

  testWidgets('prominent glass keeps its own layer inside a regular scope', (tester) async {
    await tester.pumpWidget(_host(
      const LightSkin(),
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.prominent, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), const LightSkin().accent);
  });

  testWidgets('clear glass keeps its own layer inside a regular scope', (tester) async {
    await tester.pumpWidget(_host(
      const LightSkin(),
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.clear, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(
      inner.settings.glassColor,
      GlassStyle.resolve(skin: const LightSkin(), variant: GlassVariant.clear, size: 44).glassColor,
    );
  });

  testWidgets('high contrast draws an outline', (tester) async {
    await tester.pumpWidget(_host(const DarkSkin(), _surface, highContrast: true));
    expect(find.byKey(GlassSurface.outlineKey), findsOneWidget);
    await tester.pumpWidget(_host(const DarkSkin(), _surface));
    expect(find.byKey(GlassSurface.outlineKey), findsNothing);
  });
}
