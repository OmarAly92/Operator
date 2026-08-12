import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class DarkSkin extends AppSkin {
  const DarkSkin();

  @override
  ThemeMode get themeMode => ThemeMode.dark;

  @override
  Color get bgBase => const Color(0xFF0A0B0D);

  @override
  Color get bgSide => const Color(0xFF08090B);

  @override
  Color get bgColumn => const Color(0xFF0E0F12);

  @override
  Color get bgSurface => const Color(0xFF121317);

  @override
  Color get bgElevated => const Color(0xFF15171B);

  @override
  Color get bgElevatedHover => const Color(0xFF191B20);

  @override
  Color get bgSubtle => const Color(0x0AFFFFFF);

  @override
  Color get textPrimary => const Color(0xFFF4F5F7);

  @override
  Color get textSecondary => const Color(0xFF9BA1AA);

  @override
  Color get textTertiary => const Color(0xFF646A73);

  @override
  Color get textFaint => const Color(0xFF444951);

  @override
  Color get borderSubtle => const Color(0x0FFFFFFF);

  @override
  Color get borderDefault => const Color(0x1AFFFFFF);

  @override
  Color get borderStrong => const Color(0x29FFFFFF);

  @override
  Color get blue => const Color(0xFF4D8DFF);

  @override
  Color get orange => const Color(0xFFF59F4C);

  @override
  Color get amber => const Color(0xFFE8C14A);

  @override
  Color get red => const Color(0xFFEF6B6B);

  @override
  Color get purple => const Color(0xFFA371F7);

  @override
  Color get green => const Color(0xFF74B98A);

  @override
  Color get tintBlue => const Color(0x244D8DFF);

  @override
  Color get tintOrange => const Color(0x24F59F4C);

  @override
  Color get tintAmber => const Color(0x24E8C14A);

  @override
  Color get tintRed => const Color(0x24EF6B6B);

  @override
  Color get tintGreen => const Color(0x2474B98A);

  @override
  Color get tintPurple => const Color(0x24A371F7);

  @override
  Color get onAccent => const Color(0xFF06101F);

  @override
  Color get scrim => const Color(0x99000000);

  @override
  Color get accent => const Color(0xFF4D8DFF);

  @override
  Color get accentTint => const Color(0x244D8DFF);

  @override
  Color get attention => const Color(0xFFE8C14A);
}
