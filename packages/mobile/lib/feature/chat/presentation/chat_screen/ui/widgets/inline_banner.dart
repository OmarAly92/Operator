import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

enum BannerTone { warning, danger, muted }

class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.text,
    this.action,
    this.secondary,
    this.onPressed,
    this.onSecondary,
  });

  final BannerTone tone;
  final IconData icon;
  final String text;
  final String? action;
  final String? secondary;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = switch (tone) {
      BannerTone.danger => skin.red,
      BannerTone.warning => skin.amber,
      BannerTone.muted => skin.textTertiary,
    };
    final fill = switch (tone) {
      BannerTone.danger => skin.tintRed,
      BannerTone.warning => skin.tintAmber,
      BannerTone.muted => skin.bgSubtle,
    };

    return Container(
      width: double.infinity,
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const HorizontalSpace(8),
          Expanded(
            child: AppText(
              text,
              style: AppTextStyle.style11Regular.copyWith(
                color: skin.textSecondary,
                height: 1.35,
              ),
              maxLines: 6,
            ),
          ),
          if (secondary != null)
            InkWell(
              onTap: onSecondary,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AppText(
                  secondary!,
                  style: AppTextStyle.style11SemiBold.copyWith(
                    color: skin.textTertiary,
                  ),
                ),
              ),
            ),
          if (action != null)
            InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AppText(
                  action!,
                  style: AppTextStyle.style11Bold.copyWith(color: color),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
