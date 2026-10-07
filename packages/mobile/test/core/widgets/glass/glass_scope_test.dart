import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

void main() {
  testWidgets('a glass scope keeps the 20 pt spacing its toolbars were drawn with before the native default of 8', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: GlassScope(
            variant: GlassVariant.regular,
            size: 44,
            child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 44, height: 44)),
          ),
        ),
      ),
    );
    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
  });
}
