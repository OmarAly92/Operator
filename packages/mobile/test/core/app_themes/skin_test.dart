import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

void main() {
  group('DarkSkin', () {
    const skin = DarkSkin();

    test('drives dark mode', () => expect(skin.themeMode, ThemeMode.dark));

    test('carries the opaque surface tokens', () {
      expect(skin.bgBase, const Color(0xFF18171C));
      expect(skin.bgSurface, const Color(0xFF1F1E24));
      expect(skin.textPrimary, const Color(0xFFFFFFFF));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0DFFFFFF));
      expect(skin.borderDefault, const Color(0x12FFFFFF));
      expect(skin.scrim, const Color(0x8C1A1612));
      expect(skin.tintBlue, const Color(0x1A47BFFF));
    });

    test('keeps the state hues distinct', () {
      expect(skin.blue, const Color(0xFF47BFFF));
      expect(skin.orange, const Color(0xFFE89527));
      expect(skin.amber, const Color(0xFFF0B45C));
      expect(skin.red, const Color(0xFFFF7575));
      expect(skin.green, const Color(0xFF1ACB64));
      expect(skin.purple, const Color(0xFF1F8EE0));
    });
  });

  group('LightSkin', () {
    const skin = LightSkin();

    test('drives light mode', () => expect(skin.themeMode, ThemeMode.light));

    test('darkens the state hues rather than reusing them', () {
      expect(skin.blue, const Color(0xFF1F8EE0));
      expect(skin.green, const Color(0xFF1F8A5B));
      expect(skin.red, const Color(0xFFC43A3A));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0D1A1612));
      expect(skin.borderStrong, const Color(0xFFD8CEBD));
      expect(skin.scrim, const Color(0x8C1A1612));
    });
  });
}
