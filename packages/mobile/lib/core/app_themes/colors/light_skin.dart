import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class LightSkin extends AppSkin {
  const LightSkin();

  @override
  ThemeMode get themeMode => ThemeMode.light;

  @override
  Color get bgBase => const Color(0xFFFAF7F2);

  @override
  Color get bgSide => const Color(0xFFFFFFFF);

  @override
  Color get bgColumn => const Color(0xFFFAF7F2);

  @override
  Color get bgSurface => const Color(0xFFFFFFFF);

  @override
  Color get bgElevated => const Color(0xFFF4EFE6);

  @override
  Color get bgElevatedHover => const Color(0xFFEBE4D6);

  @override
  Color get bgSubtle => const Color(0x0D1A1612);

  @override
  Color get textPrimary => const Color(0xFF1A1612);

  @override
  Color get textSecondary => const Color(0xFF3D362E);

  @override
  Color get textTertiary => const Color(0xFF6B6354);

  @override
  Color get textFaint => const Color(0xFF9C9381);

  @override
  Color get borderSubtle => const Color(0x0F1A1612);

  @override
  Color get borderDefault => const Color(0xFFEBE4D6);

  @override
  Color get borderStrong => const Color(0xFFD8CEBD);

  @override
  Color get blue => const Color(0xFF1F8EE0);

  @override
  Color get orange => const Color(0xFF96590D);

  @override
  Color get amber => const Color(0xFF856010);

  @override
  Color get red => const Color(0xFFC43A3A);

  @override
  Color get purple => const Color(0xFF1A6FB0);

  @override
  Color get green => const Color(0xFF1F8A5B);

  @override
  Color get tintBlue => const Color(0x1A1F8EE0);

  @override
  Color get tintOrange => const Color(0x24E89527);

  @override
  Color get tintAmber => const Color(0x24E89527);

  @override
  Color get tintRed => const Color(0x1AC43A3A);

  @override
  Color get tintGreen => const Color(0x241ACB64);

  @override
  Color get tintPurple => const Color(0x1A1F8EE0);

  @override
  Color get onAccent => const Color(0xFF18171C);

  @override
  Color get scrim => const Color(0x8C1A1612);

  @override
  Color get accent => const Color(0xFF1ACB64);

  @override
  Color get accentTint => const Color(0x241ACB64);

  @override
  Color get attention => const Color(0xFF1ACB64);

  @override
  Color get coral => const Color(0xFFC47A18);

  @override
  Color get shimmerBase => const Color(0xFFEFE9DD);

  @override
  Color get shimmerHi => const Color(0xFFFBF9F5);

  @override
  Color get bgChrome => const Color(0xFFFDFCFA);
}
