import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

/// Matches the prototype's confirm/remove dialog spec (`docs/design/components.md`):
/// `bgSurface` card at `radiusCard`, a full-width ghost/action button row instead of
/// trailing [TextButton]s.
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
      builder: (dialogContext) => Dialog(
        backgroundColor: skin.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                style: AppTextStyle.style16p5Bold.copyWith(color: skin.textPrimary),
                maxLines: 2,
              ),
              const VerticalSpace(8),
              AppText(
                message,
                style: AppTextStyle.style13p5Regular.copyWith(color: skin.textSecondary, height: 1.45),
                maxLines: 4,
                overflow: TextOverflow.visible,
              ),
              const VerticalSpace(16),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: cancelLabel,
                      textColor: skin.textSecondary,
                      onTap: () => Navigator.of(dialogContext).pop(false),
                      border: Border.all(color: skin.borderDefault),
                    ),
                  ),
                  const HorizontalSpace(10),
                  Expanded(
                    child: _DialogButton(
                      label: confirmLabel,
                      textColor: destructive ? Colors.white : skin.onAccent,
                      backgroundColor: destructive ? skin.red : skin.accent,
                      onTap: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    this.backgroundColor,
    this.border,
  });

  final String label;
  final Color textColor;
  final Color? backgroundColor;
  final BoxBorder? border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            ),
            child: AppText(
              label,
              style: AppTextStyle.style15SemiBold.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}
