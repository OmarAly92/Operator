import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/shaders.dart' show isLocalTest;

Widget _app({required bool shown}) => MaterialApp(
  home: GlassTheme(
    data: const GlassThemeData(brightness: Brightness.dark),
    child: Center(child: shown ? const Padding(padding: EdgeInsets.all(1), child: GlassEffect(child: SizedBox(width: 120, height: 44))) : const SizedBox(width: 10, height: 10)),
  ),
);

double? _visibility(WidgetTester tester) =>
    tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).map((layer) => layer.visibility?.value).whereType<double>().firstOrNull;

void main() {
  isLocalTest = true;

  testWidgets('a withGlassAnimation left pending by a test without a frame is cleared by the exported debugResetGlassAnimation', (tester) async {
    await tester.pumpWidget(_app(shown: false));
    withGlassAnimation(GlassAnimation.bouncy, () {});
    debugResetGlassAnimation();
    await tester.pumpWidget(_app(shown: true));
    expect(_visibility(tester), 1);
  });

  testWidgets('without the reset, the pending animation reaches the next frame and the glass materializes', (tester) async {
    await tester.pumpWidget(_app(shown: false));
    withGlassAnimation(GlassAnimation.bouncy, () {});
    await tester.pumpWidget(_app(shown: true));
    expect(_visibility(tester), 0);
    await tester.pumpAndSettle();
    debugResetGlassAnimation();
  });
}
