import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

enum GlassVariant { regular, clear, prominent }

sealed class GlassStyle {
  static const double _minSize = 20;
  static const double _maxSize = 600;

  static double sizeProgress(double size) =>
      ((size.clamp(_minSize, _maxSize) - _minSize) / (_maxSize - _minSize)).toDouble();

  static double thicknessFor(double size) => lerpDouble(10, 30, math.sqrt(sizeProgress(size)))!;

  static LiquidGlassSettings resolve({
    required AppSkin skin,
    required GlassVariant variant,
    required double size,
    bool highContrast = false,
  }) {
    final dark = skin.themeMode == ThemeMode.dark;
    final t = sizeProgress(size);
    final baseTint = switch (variant) {
      GlassVariant.regular => dark ? skin.bgSurface.withValues(alpha: 0.1) : const Color(0xFFFFFFFF).withValues(alpha: 0.58),
      GlassVariant.clear => dark ? skin.bgSurface.withValues(alpha: 0.05) : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
      GlassVariant.prominent => skin.accent.withValues(alpha: 0.85),
    };
    final tint = highContrast ? baseTint.withValues(alpha: math.min(0.92, baseTint.a + 0.3)) : baseTint;
    return LiquidGlassSettings(
      glassColor: tint,
      thickness: thicknessFor(size),
      blur: lerpDouble(2, 10, t)! * (variant == GlassVariant.clear ? 0.5 : 1),
      chromaticAberration: 0.02,
      lightAngle: 0.5 * math.pi,
      lightIntensity: lerpDouble(0.55, 0.8, t)!,
      ambientStrength: 0.1,
      refractiveIndex: 1.2,
      saturation: switch (variant) {
        GlassVariant.clear => 1.2,
        GlassVariant.regular => dark ? 1.2 : 2.0,
        GlassVariant.prominent => 1.0,
      },
      fillRatio: 0.7,
    );
  }

  static List<BoxShadow> shadows(AppSkin skin, {required double size}) {
    final dark = skin.themeMode == ThemeMode.dark;
    final t = sizeProgress(size);
    return [
      BoxShadow(
        blurStyle: BlurStyle.outer,
        color: const Color(0xFF000000).withValues(alpha: dark ? 0.06 : 0.03),
        blurRadius: lerpDouble(1, 3, t)!,
      ),
      BoxShadow(
        blurStyle: BlurStyle.outer,
        color: const Color(0xFF000000).withValues(alpha: dark ? 0.10 : 0.06),
        blurRadius: lerpDouble(10, 30, t)!,
      ),
    ];
  }
}
