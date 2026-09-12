import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart';

void main() {
  group('TerminalPalette.dark', () {
    test('uses the requested background and desktop ANSI black', () {
      expect(TerminalPalette.dark.black, const Color(0xFF616161));
      expect(TerminalPalette.dark.background, const Color(0xFF1E2022));
    });

    test('matches the desktop terminal colors', () {
      expect(TerminalPalette.dark.foreground, const Color(0xFFFFFFFF));
      expect(TerminalPalette.dark.cursor, const Color(0xFF19AAD8));
      expect(TerminalPalette.dark.red, const Color(0xFFFF8272));
      expect(TerminalPalette.dark.green, const Color(0xFFB4FA72));
      expect(TerminalPalette.dark.yellow, const Color(0xFFFEFDC2));
      expect(TerminalPalette.dark.blue, const Color(0xFFA5D5FE));
      expect(TerminalPalette.dark.magenta, const Color(0xFFFF8FFD));
      expect(TerminalPalette.dark.cyan, const Color(0xFFD0D1FE));
      expect(TerminalPalette.dark.white, const Color(0xFFF1F1F1));
      expect(TerminalPalette.dark.brightBlack, const Color(0xFF8E8E8E));
      expect(TerminalPalette.dark.brightWhite, const Color(0xFFFEFFFF));
    });
  });

  group('TerminalPalette.light', () {
    test('collapses black into the light background too', () {
      expect(TerminalPalette.light.black, const Color(0xFFF5F5F4));
      expect(TerminalPalette.light.background, const Color(0xFFF5F5F4));
    });

    test('darkens every hue rather than reusing the dark set', () {
      expect(TerminalPalette.light.foreground, const Color(0xFF24292F));
      expect(TerminalPalette.light.cursor, const Color(0xFFB45309));
      expect(TerminalPalette.light.red, const Color(0xFFA13C37));
      expect(TerminalPalette.light.green, const Color(0xFF2E6B3E));
      expect(TerminalPalette.light.blue, const Color(0xFF3B5AA6));
      expect(TerminalPalette.light.brightWhite, const Color(0xFF24292F));
    });
  });

  test('picks the palette by brightness', () {
    expect(TerminalPalette.forBrightness(Brightness.dark), same(TerminalPalette.dark));
    expect(TerminalPalette.forBrightness(Brightness.light), same(TerminalPalette.light));
  });
}
