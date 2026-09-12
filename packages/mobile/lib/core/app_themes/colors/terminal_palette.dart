import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

sealed class TerminalPalette {
  static TerminalTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  static const TerminalTheme dark = TerminalTheme(
    cursor: Color(0xFF19AAD8),
    selection: Color(0x6676A7FA),
    foreground: Color(0xFFFFFFFF),
    background: Color(0xFF1E2022),
    black: Color(0xFF616161),
    red: Color(0xFFFF8272),
    green: Color(0xFFB4FA72),
    yellow: Color(0xFFFEFDC2),
    blue: Color(0xFFA5D5FE),
    magenta: Color(0xFFFF8FFD),
    cyan: Color(0xFFD0D1FE),
    white: Color(0xFFF1F1F1),
    brightBlack: Color(0xFF8E8E8E),
    brightRed: Color(0xFFFFC4BD),
    brightGreen: Color(0xFFD6FCB9),
    brightYellow: Color(0xFFFEFDD5),
    brightBlue: Color(0xFFC1E3FE),
    brightMagenta: Color(0xFFFFB1FE),
    brightCyan: Color(0xFFE5E6FE),
    brightWhite: Color(0xFFFEFFFF),
    searchHitBackground: Color(0xFFFEFDC2),
    searchHitBackgroundCurrent: Color(0xFF19AAD8),
    searchHitForeground: Color(0xFF1E2022),
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
