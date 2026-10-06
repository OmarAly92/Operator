import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/glass_shadow.dart';

Widget _shadow() => const Center(
  child: GlassShadow(
    shape: LiquidRoundedRectangle(borderRadius: 999),
    settings: LiquidGlassSettings(),
    shadows: [BoxShadow(color: Color(0x29000000), blurRadius: 29, offset: Offset(0, 8))],
    child: SizedBox(width: 360, height: 200),
  ),
);

void main() {
  testWidgets('an offset shadow is cut out of the glass with a clip, not a save layer', (tester) async {
    await tester.pumpWidget(_shadow());
    final shadow = tester.renderObject(find.byType(GlassShadow));
    expect(shadow, paints..save()..clipPath()..rrect()..restore());
    expect(shadow, isNot(paints..something((method, arguments) => method == #saveLayer)));
  });

  testWidgets('the clip keeps the whole tail, three sigma below the glass, and hides the glass', (tester) async {
    await tester.pumpWidget(_shadow());
    final shadow = tester.renderObject<RenderBox>(find.byType(GlassShadow));
    final glass = Offset.zero & shadow.size;
    const sigma = 29 * 0.57735 + 0.5;
    expect(
      shadow,
      paints..clipPath(
        pathMatcher: isPathThat(
          includes: [glass.bottomCenter + const Offset(0, 8 + 3 * sigma), glass.centerRight + const Offset(3 * sigma, 0)],
          excludes: [glass.center, glass.topCenter + const Offset(0, 2)],
        ),
      ),
    );
  });
}
