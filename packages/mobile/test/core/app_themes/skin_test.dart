import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

void main() {
  group('DarkSkin', () {
    const skin = DarkSkin();

    test('drives dark mode', () => expect(skin.themeMode, ThemeMode.dark));

    test('carries the opaque surface tokens', () {
      expect(skin.bgBase, const Color(0xFF0A0B0D));
      expect(skin.bgSurface, const Color(0xFF121317));
      expect(skin.textPrimary, const Color(0xFFF4F5F7));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0AFFFFFF));
      expect(skin.borderDefault, const Color(0x1AFFFFFF));
      expect(skin.scrim, const Color(0x99000000));
      expect(skin.tintBlue, const Color(0x244D8DFF));
    });

    test('keeps the state hues distinct', () {
      expect(skin.blue, const Color(0xFF4D8DFF));
      expect(skin.orange, const Color(0xFFF59F4C));
      expect(skin.amber, const Color(0xFFE8C14A));
      expect(skin.red, const Color(0xFFEF6B6B));
      expect(skin.green, const Color(0xFF74B98A));
      expect(skin.purple, const Color(0xFFA371F7));
    });
  });

  group('LightSkin', () {
    const skin = LightSkin();

    test('drives light mode', () => expect(skin.themeMode, ThemeMode.light));

    test('darkens the state hues rather than reusing them', () {
      expect(skin.blue, const Color(0xFF2563EB));
      expect(skin.green, const Color(0xFF2F7D32));
      expect(skin.red, const Color(0xFFC0392B));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0A000000));
      expect(skin.borderStrong, const Color(0x33000000));
      expect(skin.scrim, const Color(0x73000000));
    });
  });
}
