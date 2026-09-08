import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class DarkSkin extends AppSkin {
  const DarkSkin();

  @override
  ThemeMode get themeMode => ThemeMode.dark;

  @override
  Color get bgBase => const Color(0xFF18171C);

  @override
  Color get bgSide => const Color(0xFF131218);

  @override
  Color get bgColumn => const Color(0xFF18171C);

  @override
  Color get bgSurface => const Color(0xFF1F1E24);

  @override
  Color get bgElevated => const Color(0xFF28262E);

  @override
  Color get bgElevatedHover => const Color(0xFF2A2832);

  @override
  Color get bgSubtle => const Color(0x0DFFFFFF);

  @override
  Color get textPrimary => const Color(0xFFFFFFFF);

  @override
  Color get textSecondary => const Color(0xFFD9D8DE);

  @override
  Color get textTertiary => const Color(0xFFA09EA8);

  @override
  Color get textFaint => const Color(0xFF6F6D78);

  @override
  Color get borderSubtle => const Color(0x0AFFFFFF);

  @override
  Color get borderDefault => const Color(0x12FFFFFF);

  @override
  Color get borderStrong => const Color(0x1FFFFFFF);

  @override
  Color get blue => const Color(0xFF47BFFF);

  @override
  Color get orange => const Color(0xFFE89527);

  @override
  Color get amber => const Color(0xFFF0B45C);

  @override
  Color get red => const Color(0xFFFF7575);

  @override
  Color get purple => const Color(0xFF1F8EE0);

  @override
  Color get green => const Color(0xFF1ACB64);

  @override
  Color get tintBlue => const Color(0x1A47BFFF);

  @override
  Color get tintOrange => const Color(0x29E89527);

  @override
  Color get tintAmber => const Color(0x29E89527);

  @override
  Color get tintRed => const Color(0x24FF7575);

  @override
  Color get tintGreen => const Color(0x291ACB64);

  @override
  Color get tintPurple => const Color(0x1A47BFFF);

  @override
  Color get onAccent => const Color(0xFF18171C);

  @override
  Color get scrim => const Color(0x8C1A1612);

  @override
  Color get accent => const Color(0xFF1ACB64);

  @override
  Color get accentTint => const Color(0x291ACB64);

  @override
  Color get attention => const Color(0xFF1ACB64);

  @override
  Color get coral => const Color(0xFFE89527);

  @override
  Color get shimmerBase => const Color(0xFF26242D);

  @override
  Color get shimmerHi => const Color(0xFF332F3C);

  @override
  Color get bgChrome => const Color(0xFF1B1A20);
}
