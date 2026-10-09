import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

LiquidGlassSettings _drawn(LiquidGlassLayer layer) => layer.settingsSource?.settings ?? layer.settings;

LiquidGlassSettings _row(double side, {Brightness brightness = Brightness.dark, Glass glass = Glass.regular}) =>
    GlassMaterial.resolve(glass: glass, shorterSide: side, brightness: brightness).toSettings(tint: glass.tintColor);

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) => MaterialApp(
  home: GlassTheme(data: GlassThemeData(brightness: brightness), child: Align(alignment: Alignment.topLeft, child: child)),
);

Widget _glasses(List<double> sides) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [for (final side in sides) GlassEffect(child: SizedBox.square(dimension: side))],
);

LiquidGlassLayer _containerLayer(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).first;

void main() {
  isLocalTest = true;

  testWidgets('a container takes the material row of its members size, in its first frame', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64]))));
    expect(_drawn(_containerLayer(tester)), _row(64));
    expect(_drawn(_containerLayer(tester)), isNot(_row(88)));
  });

  testWidgets('a container with an explicit side keeps that row whatever its members measure', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(side: 88, child: _glasses([64, 64]))));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(88));
  });

  testWidgets('a container of mixed sizes uses the row of its median member', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 88, 200]))));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(88));
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 44, 200]))));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(44));
  });

  testWidgets('the row follows members that resize, join and leave', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 44]))));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(44));
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80, 80]))));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(80));
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80, 80, 200, 200, 200]))));
    await tester.pumpAndSettle();
    expect(_drawn(_containerLayer(tester)), _row(200));
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80]))));
    await tester.pumpAndSettle();
    expect(_drawn(_containerLayer(tester)), _row(80));
  });

  testWidgets('the row re-resolves when the appearance flips, at the same size', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64]))));
    await tester.pump();
    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64])), brightness: Brightness.light));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(64, brightness: Brightness.light));
  });

  testWidgets('a union of 64 pt members draws with the row of 64 pt glass, not of 88', (tester) async {
    final namespace = GlassNamespace();
    await tester.pumpWidget(_host(GlassEffectContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in ['a', 'b']) GlassEffect(key: ValueKey(key), union: GlassEffectUnion('u', namespace), child: const SizedBox.square(dimension: 64)),
        ],
      ),
    )));
    await tester.pump();
    expect(_drawn(_containerLayer(tester)), _row(64));
  });
}
