import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

double _channel(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Map<String, Color> _surfaces(AppSkin skin) => {
      'bgBase': skin.bgBase,
      'bgSurface': skin.bgSurface,
      'bgElevated': skin.bgElevated,
      'accentTint on bgSurface': Color.alphaBlend(skin.accentTint, skin.bgSurface),
      'accentTint on bgBase': Color.alphaBlend(skin.accentTint, skin.bgBase),
      'tintGreen on bgBase': Color.alphaBlend(skin.tintGreen, skin.bgBase),
    };

void main() {
  test('light accentText reads at 4.5:1 or better on every light surface it sits on', () {
    const skin = LightSkin();
    for (final entry in _surfaces(skin).entries) {
      expect(contrast(skin.accentText, entry.value), greaterThanOrEqualTo(4.5), reason: entry.key);
    }
  });

  test('the bright accent is too faint for text in light mode, which is why accentText exists', () {
    const skin = LightSkin();
    expect(contrast(skin.accent, skin.bgBase), lessThan(3));
  });

  test('dark accentText is the unchanged accent and reads at 4.5:1 or better', () {
    const skin = DarkSkin();
    expect(skin.accentText, skin.accent);
    for (final entry in _surfaces(skin).entries) {
      expect(contrast(skin.accentText, entry.value), greaterThanOrEqualTo(4.5), reason: entry.key);
    }
  });
}
