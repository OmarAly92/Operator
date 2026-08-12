import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';

sealed class AppThemes {
  static ThemeData fromSkin(AppSkin skin) {
    final brightness = skin.themeMode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: skin.bgBase,
      appBarTheme: AppBarTheme(
        backgroundColor: skin.bgSurface,
        titleTextStyle: AppTextStyle.style17SemiBold.copyWith(
          color: skin.textPrimary,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: skin.accent,
        selectionColor: skin.accentTint,
      ),
    );
  }
}
