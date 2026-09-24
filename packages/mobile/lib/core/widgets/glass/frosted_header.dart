import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';

class FrostedCircleButton extends StatelessWidget {
  const FrostedCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.diameter = GlassMetrics.sheetHeaderButton,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? semanticLabel;
  final double diameter;
  final Color? foreground;

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
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
  const FrostedCapsule({super.key, required this.child, this.extent = GlassMetrics.sheetHeaderButton});

  final Widget child;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final radius = BorderRadius.circular(extent / 2);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
