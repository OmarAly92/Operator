import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionsHeader extends StatelessWidget {
  const ConnectionsHeader({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Row(
      children: [
        Image.asset('assets/images/mascot.png', width: 28, height: 28),
        const HorizontalSpace(8),
        AppText('Operator', style: AppTextStyle.style15SemiBold),
        const Spacer(),
        AppContainer(
          onTap: onAdd,
          width: 32,
          height: 32,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
          backgroundColor: skin.bgElevated,
          child: Center(child: Icon(Icons.add, size: 19, color: skin.textSecondary)),
        ),
      ],
    );
  }
}
