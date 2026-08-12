import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionFailureBanner extends StatelessWidget {
  const ConnectionFailureBanner({super.key, required this.copy});

  final ConnectionErrorCopy copy;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      backgroundColor: skin.tintRed,
      border: Border.all(color: skin.red),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(copy.title, style: AppTextStyle.style13SemiBold.copyWith(color: skin.red), maxLines: 2),
          const VerticalSpace(4),
          AppText(copy.message, style: AppTextStyle.style12Regular.copyWith(color: skin.textPrimary), maxLines: 4),
          if (copy.showLocalNetworkHint) ...[
            const VerticalSpace(8),
            AppText(kLocalNetworkHint, style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary), maxLines: 4),
          ],
        ],
      ),
    );
  }
}
