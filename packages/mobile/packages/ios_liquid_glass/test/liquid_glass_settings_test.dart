import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';

void main() {
  test('fillRatio defaults to upstream symmetric look', () {
    expect(const LiquidGlassSettings().fillRatio, 0.8);
  });

  test('copyWith changes and preserves fillRatio', () {
    const base = LiquidGlassSettings(fillRatio: 0.25);
    expect(base.copyWith(thickness: 3).fillRatio, 0.25);
    expect(base.copyWith(fillRatio: 0.5).fillRatio, 0.5);
  });

  test('fillRatio takes part in equality', () {
    expect(const LiquidGlassSettings(fillRatio: 0.2), isNot(const LiquidGlassSettings(fillRatio: 0.3)));
  });

  test('the iOS look defaults leave the backdrop untouched', () {
    const settings = LiquidGlassSettings();
    expect([settings.toneBlack, settings.toneMid, settings.toneWhite], [0, 0.5, 1]);
    expect([settings.tintBlack, settings.tintWhite], [1, 1]);
    expect([settings.outline, settings.outlineTop, settings.specular, settings.sheen], [0, 0, 0, 0]);
  });

  test('visibility fades the tone curve and edge light towards no effect', () {
    const settings = LiquidGlassSettings(
      visibility: 0.5,
      toneBlack: 0.2,
      toneMid: 0.7,
      toneWhite: 0.6,
      outline: 0.4,
      outlineTop: 0.2,
      specular: 0.8,
      sheen: 0.1,
    );
    expect(settings.effectiveToneBlack, closeTo(0.1, 1e-9));
    expect(settings.effectiveToneMid, closeTo(0.6, 1e-9));
    expect(settings.effectiveToneWhite, closeTo(0.8, 1e-9));
    expect(settings.effectiveOutline, closeTo(0.2, 1e-9));
    expect(settings.effectiveOutlineTop, closeTo(0.1, 1e-9));
    expect(settings.effectiveSpecular, closeTo(0.4, 1e-9));
    expect(settings.effectiveSheen, closeTo(0.05, 1e-9));
  });

  test('copyWith and equality cover every iOS look field', () {
    const base = LiquidGlassSettings();
    final changed = [
      base.copyWith(toneBlack: 0.1),
      base.copyWith(toneMid: 0.4),
      base.copyWith(toneWhite: 0.9),
      base.copyWith(tintBlack: 0.8),
      base.copyWith(tintWhite: 1.1),
      base.copyWith(outline: 0.3),
      base.copyWith(outlineTop: 0.2),
      base.copyWith(outlineWidth: 2),
      base.copyWith(specular: 0.5),
      base.copyWith(specularWidth: 3),
      base.copyWith(specularPower: 4),
      base.copyWith(specularFill: 0.1),
      base.copyWith(sheen: 0.2),
      base.copyWith(sheenWidth: 5),
    ];
    for (final settings in changed) {
      expect(settings, isNot(base));
    }
    expect(base.copyWith(toneMid: 0.4).copyWith(outline: 0.3).toneMid, 0.4);
  });

  test('a new outline width rebuilds the cached geometry, a new outline strength does not', () {
    const base = LiquidGlassSettings(outlineWidth: 0.5);
    expect(base.copyWith(outlineWidth: 0.8).requiresGeometryRebuild(base), isTrue);
    expect(base.copyWith(outline: 0.9).requiresGeometryRebuild(base), isFalse);
  });
}
