import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';

sealed class FrostedMaterial {
  static const double blurSigma = 14;
  static const double saturation = 1.7;
  static const double lightenAlpha = 0.045;

  static Widget backdrop({required double frost, required Widget child}) =>
      frost <= 0 ? child : BackdropFilter(filter: filter(frost), child: child);

  static ui.ImageFilter filter([double strength = 1]) {
    final s = 1 + (saturation - 1) * strength;
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final sigma = blurSigma * strength;
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      inner: ColorFilter.matrix([
        r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0,
        r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
        r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    );
  }
}

class FrostedCircleButton extends StatelessWidget {
  const FrostedCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.diameter = GlassMetrics.sheetHeaderButton,
    this.foreground,
    this.frost = 1,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? semanticLabel;
  final double diameter;
  final Color? foreground;
  final double frost;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final glyphSize = ((22 * diameter / GlassMetrics.hitTarget) * 2).round() / 2;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onPressed();
        },
        child: ClipOval(
          child: FrostedMaterial.backdrop(
            frost: frost,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: skin.textPrimary.withValues(alpha: 0.08),
                border: Border.all(color: skin.borderStrong, width: 0.5),
              ),
              child: Icon(icon, size: glyphSize, color: foreground ?? skin.textPrimary, semanticLabel: semanticLabel),
            ),
          ),
        ),
      ),
    );
  }
}

class FrostedCapsule extends StatelessWidget {
  const FrostedCapsule({super.key, required this.child, this.extent = GlassMetrics.sheetHeaderButton, this.frost = 1});

  final Widget child;
  final double extent;
  final double frost;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final radius = BorderRadius.circular(extent / 2);
    return ClipRRect(
      borderRadius: radius,
      child: FrostedMaterial.backdrop(
        frost: frost,
        child: Container(
          constraints: BoxConstraints(minWidth: extent, minHeight: extent, maxHeight: extent),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: skin.textPrimary.withValues(alpha: 0.08),
            border: Border.all(color: skin.borderStrong, width: 0.5),
          ),
          child: Center(widthFactor: 1, child: child),
        ),
      ),
    );
  }
}
