import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart';

void main() {
  group('TerminalPalette.dark', () {
    test('collapses black into the background so a filled row draws no bar', () {
      expect(TerminalPalette.dark.black, const Color(0xFF0C0D10));
      expect(TerminalPalette.dark.background, const Color(0xFF0C0D10));
    });

    test('carries the ANSI hues', () {
      expect(TerminalPalette.dark.foreground, const Color(0xFFF4F5F7));
      expect(TerminalPalette.dark.cursor, const Color(0xFFF59F4C));
      expect(TerminalPalette.dark.red, const Color(0xFFF05D5E));
      expect(TerminalPalette.dark.green, const Color(0xFF44C97A));
      expect(TerminalPalette.dark.yellow, const Color(0xFFE5C34B));
      expect(TerminalPalette.dark.blue, const Color(0xFF5B9CFF));
      expect(TerminalPalette.dark.magenta, const Color(0xFFC678DD));
      expect(TerminalPalette.dark.cyan, const Color(0xFF56B6C2));
      expect(TerminalPalette.dark.white, const Color(0xFFD7DAE0));
      expect(TerminalPalette.dark.brightBlack, const Color(0xFF7F8792));
      expect(TerminalPalette.dark.brightWhite, const Color(0xFFF4F5F7));
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
