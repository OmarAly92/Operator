import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: skin.textFaint),
            const VerticalSpace(12),
            AppText(title, style: AppTextStyle.style15SemiBold),
            const VerticalSpace(6),
            AppText(
              message,
              style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
              maxLines: 4,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const VerticalSpace(16), action!],
          ],
        ),
      ),
    );
  }
}
