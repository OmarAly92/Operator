import 'package:expressive_snack/expressive_snack.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

/// Matches the prototype's `S.toast` spec (`docs/design/motion.md`'s
/// `saSlideUp` toast entrance) via `package:expressive_snack`'s
/// spring-driven stacked pill, themed with [AppSkin] colors instead of the
/// ambient Material theme's inverse-surface defaults.
sealed class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    bool destructive = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final skin = context.skin;
    showExpressiveSnack(
      context: context,
      message: message,
      icon: icon,
      backgroundColor: destructive ? skin.red : skin.bgElevated,
      foregroundColor: destructive ? Colors.white : skin.textPrimary,
      iconBackgroundColor: destructive ? Colors.white24 : skin.accentTint,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}
