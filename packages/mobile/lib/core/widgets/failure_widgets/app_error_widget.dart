import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, this.failure, this.onPressed});

  final Failure? failure;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: context.skin.red, size: 48),
          const VerticalSpace(14),
          AppText(
            failure?.message ?? 'Something went wrong',
            style: AppTextStyle.style15SemiBold,
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          if (onPressed != null) ...[
            const VerticalSpace(20),
            PrimaryButton(text: 'Retry', onPressed: onPressed),
          ],
        ],
      ),
    ),
  );
}
