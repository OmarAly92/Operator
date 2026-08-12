import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

sealed class AppDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final skin = context.skin;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: skin.bgElevated,
        title: AppText(title, style: AppTextStyle.style16SemiBold, maxLines: 2),
        content: AppText(
          message,
          style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: AppText(cancelLabel, style: AppTextStyle.style14Medium.copyWith(color: skin.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: AppText(
              confirmLabel,
              style: AppTextStyle.style14SemiBold.copyWith(color: destructive ? skin.red : skin.accent),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
