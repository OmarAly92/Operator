import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  const accent = Color(0xFF1ACB64);
  const table = {
    'dark.regular.44': {'frost': 2.0, 'toneBlack': 0.1},
    'dark.regular.88': {'frost': 4.0, 'toneBlack': 0.2},
    'dark.regular.200': {'frost': 8.0, 'toneBlack': 0.3},
    'dark.tinted.88': {'tintAmount': 0.9},
    'dark.clear.88': {'frost': 1.0},
    'dark.reduceTransparency.88': {'toneBlack': 0.16, 'toneWhite': 0.16},
    'dark.increaseContrast.88': {'hairline': 0.9},
    'light.regular.88': {'frost': 5.0},
  };

  GlassMaterial resolve({
    Glass glass = Glass.regular,
    double side = 88,
    Brightness brightness = Brightness.dark,
    GlassAccessibilityData accessibility = const GlassAccessibilityData(),
  }) => GlassMaterial.resolve(glass: glass, shorterSide: side, brightness: brightness, accessibility: accessibility, table: table);

  test('reads the row for the appearance at an anchor', () {
    expect(resolve()['frost'], 4);
    expect(resolve(brightness: Brightness.light)['frost'], 5);
  });

  test('interpolates on log size between anchors', () {
    final side = math.sqrt(44 * 88);
    expect(resolve(side: side)['frost'], closeTo(3, 1e-9));
    expect(resolve(side: side)['toneBlack'], closeTo(0.15, 1e-9));
  });

  test('clamps outside the anchors', () {
    expect(resolve(side: 10)['frost'], 2);
    expect(resolve(side: 900)['frost'], 8);
  });

  test('missing fields fall back to defaults', () {
    expect(resolve()['saturation'], GlassMaterial.defaults['saturation']);
  });

  test('picks the row from the glass and accessibility, accessibility first', () {
    expect(GlassMaterial.rowFor(Glass.regular, const GlassAccessibilityData()), 'regular');
    expect(GlassMaterial.rowFor(Glass.clear, const GlassAccessibilityData()), 'clear');
    expect(GlassMaterial.rowFor(Glass.regular.tint(accent), const GlassAccessibilityData()), 'tinted');
    expect(GlassMaterial.rowFor(Glass.clear, const GlassAccessibilityData(increaseContrast: true)), 'increaseContrast');
    expect(
      GlassMaterial.rowFor(Glass.regular, const GlassAccessibilityData(reduceTransparency: true, increaseContrast: true)),
      'reduceTransparency',
    );
    expect(resolve(glass: Glass.regular.tint(accent))['tintAmount'], 0.9);
    expect(resolve(accessibility: const GlassAccessibilityData(reduceTransparency: true))['toneWhite'], 0.16);
  });

  test('overrides replace fields by name', () {
    final material = resolve().withOverrides({'frost': 12, 'toneMid': 0.4});
    expect(material['frost'], 12);
    expect(material['toneMid'], 0.4);
    expect(material['toneBlack'], 0.2);
  });

  test('settings carry every rendered field and the tint', () {
    final material = GlassMaterial(const {
      'thickness': 20,
      'dispersion': 0.03,
      'frost': 9,
      'saturation': 1.4,
      'toneBlack': 0.1,
      'toneMid': 0.4,
      'toneWhite': 0.8,
      'tintAmount': 0.9,
      'tintBlack': 0.8,
      'tintWhite': 1.1,
      'hairline': 0.3,
      'specular': 0.5,
    });
    final settings = material.toSettings(tint: accent);
    expect(settings.thickness, 20);
    expect(settings.chromaticAberration, 0.03);
    expect(settings.blur, 9);
    expect(settings.saturation, 1.4);
    expect([settings.toneBlack, settings.toneMid, settings.toneWhite], [0.1, 0.4, 0.8]);
    expect([settings.tintBlack, settings.tintWhite], [0.8, 1.1]);
    expect(settings.glassColor, accent.withValues(alpha: 0.9));
    expect(settings.hairline, 0.3);
    expect(settings.specular, 0.5);
    expect(material.toSettings().glassColor.a, 0);
  });

  test('shadows are one outer shadow, or none at zero opacity', () {
    const shadow = GlassMaterial({'shadowOpacity': 0.2, 'shadowBlur': 10, 'shadowOffsetY': 3});
    expect(shadow.shadows.single.blurStyle, BlurStyle.outer);
    expect(shadow.shadows.single.offset, const Offset(0, 3));
    expect(const GlassMaterial({'shadowOpacity': 0}).shadows, isEmpty);
  });

  test('the shipped table has every row at every anchor', () {
    for (final appearance in ['dark', 'light']) {
      for (final row in ['regular', 'clear', 'tinted', 'reduceTransparency', 'increaseContrast']) {
        for (final anchor in GlassMaterial.anchors) {
          expect(ios27Table.containsKey('$appearance.$row.${anchor.toInt()}'), isTrue, reason: '$appearance.$row.$anchor');
        }
      }
    }
  });

  test('tinted glass keeps its tint under reduce transparency', () {
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['tintAmount'], 0.9);
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['toneWhite'], 0.16);
  });
}
