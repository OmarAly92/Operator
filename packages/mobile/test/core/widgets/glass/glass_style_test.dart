import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

void main() {
  const light = LightSkin();
  const dark = DarkSkin();

  group('GlassStyle.thicknessFor', () {
    test('grows with size', () {
      expect(GlassStyle.thicknessFor(62), greaterThan(GlassStyle.thicknessFor(44)));
      expect(GlassStyle.thicknessFor(300), greaterThan(GlassStyle.thicknessFor(62)));
    });

    test('is clamped at both ends', () {
      expect(GlassStyle.thicknessFor(0), GlassStyle.thicknessFor(20));
      expect(GlassStyle.thicknessFor(2000), GlassStyle.thicknessFor(600));
    });
  });

  group('GlassStyle.resolve', () {
    test('clear is more transparent than regular', () {
      final regular = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      final clear = GlassStyle.resolve(skin: light, variant: GlassVariant.clear, size: 62);
      expect(clear.glassColor.a, lessThan(regular.glassColor.a));
    });

    test('prominent is tinted with the accent', () {
      final prominent = GlassStyle.resolve(skin: light, variant: GlassVariant.prominent, size: 44);
      expect(prominent.glassColor.withValues(alpha: 1), light.accent);
    });

    test('light and dark tint differently', () {
      final l = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      final d = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62);
      expect(l.glassColor, isNot(d.glassColor));
    });

    test('high contrast raises tint opacity', () {
      final normal = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62);
      final contrast = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62, highContrast: true);
      expect(contrast.glassColor.a, greaterThan(normal.glassColor.a));
    });

    test('uses a near-uniform fill', () {
      final s = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      expect(s.fillRatio, greaterThan(0.5));
    });

    test('bigger glass blurs more', () {
      final small = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 44);
      final big = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 400);
      expect(big.blur, greaterThan(small.blur));
    });
  });

  test('shadows are two outer-blur layers', () {
    final shadows = GlassStyle.shadows(light, size: 62);
    expect(shadows, hasLength(2));
    expect(shadows.every((s) => s.blurStyle == BlurStyle.outer), isTrue);
  });

  test('bigger glass casts a softer, larger ambient shadow', () {
    final small = GlassStyle.shadows(light, size: 44);
    final big = GlassStyle.shadows(light, size: 400);
    expect(big[1].blurRadius, greaterThan(small[1].blurRadius));
  });

  test('dark shadows keep their approved values', () {
    for (final size in [38.0, 48.0, 62.0, 400.0]) {
      final t = GlassStyle.sizeProgress(size);
      final shadows = GlassStyle.shadows(dark, size: size);
      expect(shadows[0].color, const Color(0xFF000000).withValues(alpha: 0.06));
      expect(shadows[0].blurRadius, moreOrLessEquals(1 + 2 * t, epsilon: 1e-9));
      expect(shadows[1].color, const Color(0xFF000000).withValues(alpha: 0.10));
      expect(shadows[1].blurRadius, moreOrLessEquals(24 + 16 * t, epsilon: 1e-9));
    }
  });

  test('light shadows are stronger than dark so glass lifts off cream and white', () {
    final l = GlassStyle.shadows(light, size: 48);
    final d = GlassStyle.shadows(dark, size: 48);
    expect(l[0].color.a, greaterThan(d[0].color.a));
    expect(l[0].blurRadius, greaterThan(d[0].blurRadius));
    expect(l[1].color.a, greaterThan(d[1].color.a));
  });

  test('only light has a glass rim', () {
    expect(light.glassRim.a, greaterThan(0));
    expect(dark.glassRim.a, 0);
  });
}
