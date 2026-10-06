import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/material/ios27.dart';

@immutable
class GlassMaterial {
  const GlassMaterial(this.values);

  static const List<double> anchors = [44, 88, 200];

  static const Map<String, double> defaults = {
    'thickness': 18,
    'refractiveIndex': 1.2,
    'dispersion': 0.02,
    'frost': 4,
    'toneBlack': 0,
    'toneMid': 0.5,
    'toneWhite': 1,
    'saturation': 1.2,
    'tintAmount': 0,
    'tintBlack': 1,
    'tintWhite': 1,
    'outline': 0,
    'outlineTop': 0,
    'outlineWidth': 0.5,
    'specular': 0,
    'specularWidth': 0.65,
    'specularPower': 2,
    'specularFill': 0.9,
    'sheen': 0,
    'sheenWidth': 2.5,
    'lightAngle': 1.5708,
    'shadowOffsetY': 0,
    'shadowBlur': 0,
    'shadowOpacity': 0,
  };

  final Map<String, double> values;

  double operator [](String name) => values[name] ?? defaults[name]!;

  GlassMaterial lerp(GlassMaterial other, double t) => GlassMaterial({
    for (final name in defaults.keys) name: this[name] + (other[name] - this[name]) * t,
  });

  GlassMaterial withOverrides(Map<String, double> overrides) =>
      overrides.isEmpty ? this : GlassMaterial({...values, ...overrides});

  LiquidGlassSettings toSettings({Color? tint}) => LiquidGlassSettings(
    thickness: this['thickness'],
    refractiveIndex: this['refractiveIndex'],
    chromaticAberration: this['dispersion'],
    blur: this['frost'],
    toneBlack: this['toneBlack'],
    toneMid: this['toneMid'],
    toneWhite: this['toneWhite'],
    saturation: this['saturation'],
    glassColor: tint == null ? const Color(0x00000000) : tint.withValues(alpha: this['tintAmount']),
    tintBlack: this['tintBlack'],
    tintWhite: this['tintWhite'],
    outline: this['outline'],
    outlineTop: this['outlineTop'],
    outlineWidth: this['outlineWidth'],
    specular: this['specular'],
    specularWidth: this['specularWidth'],
    specularPower: this['specularPower'],
    specularFill: this['specularFill'],
    sheen: this['sheen'],
    sheenWidth: this['sheenWidth'],
    lightAngle: this['lightAngle'],
  );

  List<BoxShadow> get shadows => this['shadowOpacity'] <= 0
      ? const []
      : [
          BoxShadow(
            blurStyle: BlurStyle.outer,
            color: const Color(0xFF000000).withValues(alpha: this['shadowOpacity']),
            blurRadius: this['shadowBlur'],
            offset: Offset(0, this['shadowOffsetY']),
          ),
        ];

  static String rowFor(Glass glass, GlassAccessibilityData accessibility) {
    if (accessibility.reduceTransparency) return 'reduceTransparency';
    if (accessibility.increaseContrast) return 'increaseContrast';
    if (glass.kind == GlassKind.clear) return 'clear';
    return glass.tintColor == null ? 'regular' : 'tinted';
  }

  static GlassMaterial resolve({
    required Glass glass,
    required double shorterSide,
    required Brightness brightness,
    GlassAccessibilityData accessibility = const GlassAccessibilityData(),
    Map<String, Map<String, double>> table = ios27Table,
  }) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';
    final row = rowFor(glass, accessibility);
    final material = _resolveRow(appearance, row, shorterSide, table);
    if ((row == 'reduceTransparency' || row == 'increaseContrast') && glass.kind == GlassKind.regular && glass.tintColor != null) {
      final tinted = _resolveRow(appearance, 'tinted', shorterSide, table);
      return material.withOverrides({
        'tintAmount': tinted['tintAmount'],
        'tintBlack': tinted['tintBlack'],
        'tintWhite': tinted['tintWhite'],
      });
    }
    return material;
  }

  static GlassMaterial _resolveRow(
    String appearance,
    String row,
    double shorterSide,
    Map<String, Map<String, double>> table,
  ) {
    GlassMaterial at(double anchor) => GlassMaterial(table['$appearance.$row.${anchor.toInt()}'] ?? const {});
    final side = shorterSide.clamp(anchors.first, anchors.last);
    for (var i = 0; i < anchors.length - 1; i++) {
      final low = anchors[i], high = anchors[i + 1];
      if (side <= high) {
        final t = (math.log(side) - math.log(low)) / (math.log(high) - math.log(low));
        if (t <= 0) return at(low);
        if (t >= 1) return at(high);
        return at(low).lerp(at(high), t);
      }
    }
    return at(anchors.last);
  }
}
