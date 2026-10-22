import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

Widget _app({required bool reduceMotion}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Center(child: LiquidStretch(child: SizedBox(width: 100, height: 40))),
  ),
);

void main() {
  testWidgets('LiquidStretch stretches a drag normally and does nothing under Reduce Motion', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: false));
    expect(find.byType(RawLiquidStretch), findsOneWidget);
    await tester.pumpWidget(_app(reduceMotion: true));
    expect(find.byType(RawLiquidStretch), findsNothing);
    expect(find.byType(Transform), findsNothing);
  });
}
