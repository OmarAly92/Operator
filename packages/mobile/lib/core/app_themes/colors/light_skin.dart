import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class LightSkin extends AppSkin {
  const LightSkin();

  @override
  ThemeMode get themeMode => ThemeMode.light;

  @override
  Color get bgBase => const Color(0xFFF2F2F7);

  @override
  Color get bgSide => const Color(0xFFECEEF2);

  @override
  Color get bgColumn => const Color(0xFFF7F7FA);

  @override
  Color get bgSurface => const Color(0xFFFFFFFF);

  @override
  Color get bgElevated => const Color(0xFFFFFFFF);

  @override
  Color get bgElevatedHover => const Color(0xFFECECF0);

  @override
  Color get bgSubtle => const Color(0x0A000000);

  @override
  Color get textPrimary => const Color(0xFF1A1A1A);

  @override
  Color get textSecondary => const Color(0xFF666666);

  @override
  Color get textTertiary => const Color(0xFF8E8E93);

  @override
  Color get textFaint => const Color(0xFFB8B8BD);

  @override
  Color get borderSubtle => const Color(0x0F000000);

  @override
  Color get borderDefault => const Color(0x1F000000);

  @override
  Color get borderStrong => const Color(0x33000000);

  @override
  Color get blue => const Color(0xFF2563EB);

  @override
  Color get orange => const Color(0xFFB45309);

  @override
  Color get amber => const Color(0xFF946200);

  @override
  Color get red => const Color(0xFFC0392B);

  @override
  Color get purple => const Color(0xFF7C3AED);

  @override
  Color get green => const Color(0xFF2F7D32);

  @override
  Color get tintBlue => const Color(0x1F2563EB);

  @override
  Color get tintOrange => const Color(0x1FB45309);

  @override
  Color get tintAmber => const Color(0x1F946200);

  @override
  Color get tintRed => const Color(0x1FC0392B);

  @override
  Color get tintGreen => const Color(0x1F2F7D32);

  @override
  Color get tintPurple => const Color(0x1F7C3AED);

  @override
  Color get onAccent => const Color(0xFFFFFFFF);

  @override
  Color get scrim => const Color(0x73000000);

  @override
  Color get accent => const Color(0xFF2563EB);

  @override
  Color get accentTint => const Color(0x1F2563EB);

  @override
  Color get attention => const Color(0xFF946200);
}
