import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_pill.dart';

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

  test('attentionText reads at 4.5:1 or better in both skins, and dark keeps the attention colour', () {
    for (final skin in const <AppSkin>[LightSkin(), DarkSkin()]) {
      for (final entry in _surfaces(skin).entries) {
        expect(contrast(skin.attentionText, entry.value), greaterThanOrEqualTo(4.5), reason: '${skin.themeMode.name} ${entry.key}');
      }
    }
    expect(const DarkSkin().attentionText, const DarkSkin().attention);
    expect(contrast(const LightSkin().attention, const LightSkin().bgBase), lessThan(3));
  });

  testWidgets('an active pill label reads at 4.5:1 on its green tint over cream and white', (tester) async {
    const skin = LightSkin();
    await tester.pumpWidget(
      SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(home: Scaffold(body: AppPill(label: 'Open', active: true))),
        ),
      ),
    );
    final color = tester.widget<Text>(find.text('Open')).style!.color!;
    for (final base in [skin.bgBase, skin.bgSurface]) {
      expect(contrast(color, Color.alphaBlend(skin.tintGreen, base)), greaterThanOrEqualTo(4.5));
    }
  });
}
