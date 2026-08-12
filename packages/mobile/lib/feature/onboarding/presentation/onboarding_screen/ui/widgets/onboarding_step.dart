import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class OnboardingStep extends StatelessWidget {
  const OnboardingStep({super.key, required this.n, required this.title, required this.hint});

  final int n;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: skin.tintBlue,
            child: AppText('$n', style: AppTextStyle.style12SemiBold.copyWith(color: skin.blue)),
          ),
          const HorizontalSpace(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, style: AppTextStyle.style14SemiBold, maxLines: 2),
                const VerticalSpace(2),
                AppText(hint, style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary), maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
