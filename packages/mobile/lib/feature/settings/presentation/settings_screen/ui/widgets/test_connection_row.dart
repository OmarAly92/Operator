import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';

class TestConnectionRow extends StatelessWidget {
  const TestConnectionRow({
    super.key,
    required this.loading,
    required this.disabled,
    required this.value,
    required this.valueColor,
    required this.onTap,
  });

  final bool loading;
  final bool disabled;
  final String? value;
  final Color? valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return SettingsRow(
      icon: Icons.wifi_tethering,
      label: 'Test connection',
      disabled: disabled,
      onTap: disabled ? null : onTap,
      trailing: loading
          ? const SizedBox(height: 18, width: 18, child: AppExpressiveLoader())
          : AppText(
              value ?? 'Not tested',
              style: AppTextStyle.style13Regular.copyWith(color: valueColor ?? skin.textTertiary),
            ),
    );
  }
}
