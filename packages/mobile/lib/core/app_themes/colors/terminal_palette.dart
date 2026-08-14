import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

sealed class TerminalPalette {
  static TerminalTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  /// `black` is collapsed into the background on purpose: a TUI that fills a row
  /// with "black" must draw an invisible band, not a bar.
  static const TerminalTheme dark = TerminalTheme(
    cursor: Color(0xFFF59F4C),
    selection: Color(0x405B9CFF),
    foreground: Color(0xFFF4F5F7),
    background: Color(0xFF0C0D10),
    black: Color(0xFF0C0D10),
    red: Color(0xFFF05D5E),
    green: Color(0xFF44C97A),
    yellow: Color(0xFFE5C34B),
    blue: Color(0xFF5B9CFF),
    magenta: Color(0xFFC678DD),
    cyan: Color(0xFF56B6C2),
    white: Color(0xFFD7DAE0),
    brightBlack: Color(0xFF7F8792),
    brightRed: Color(0xFFFF7B7C),
    brightGreen: Color(0xFF62DF91),
    brightYellow: Color(0xFFF2D66D),
    brightBlue: Color(0xFF79B1FF),
    brightMagenta: Color(0xFFD99AEE),
    brightCyan: Color(0xFF79D4DF),
    brightWhite: Color(0xFFF4F5F7),
    searchHitBackground: Color(0xFFE5C34B),
    searchHitBackgroundCurrent: Color(0xFFF59F4C),
    searchHitForeground: Color(0xFF0C0D10),
  );

  static const TerminalTheme light = TerminalTheme(
    cursor: Color(0xFFB45309),
    selection: Color(0x403B5AA6),
    foreground: Color(0xFF24292F),
    background: Color(0xFFF5F5F4),
    black: Color(0xFFF5F5F4),
    red: Color(0xFFA13C37),
    green: Color(0xFF2E6B3E),
    yellow: Color(0xFF87660F),
    blue: Color(0xFF3B5AA6),
    magenta: Color(0xFF7B5799),
    cyan: Color(0xFF3D7A7A),
    white: Color(0xFF666D75),
    brightBlack: Color(0xFF4C535B),
    brightRed: Color(0xFF7E3330),
    brightGreen: Color(0xFF265231),
    brightYellow: Color(0xFF6B5108),
    brightBlue: Color(0xFF31487F),
    brightMagenta: Color(0xFF5F4476),
    brightCyan: Color(0xFF316061),
    brightWhite: Color(0xFF24292F),
    searchHitBackground: Color(0xFF87660F),
    searchHitBackgroundCurrent: Color(0xFFB45309),
    searchHitForeground: Color(0xFFF5F5F4),
  );
}
