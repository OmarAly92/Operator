import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final void Function()? onTap;

  void Function()? get _onTap {
    final handler = onTap;
    if (handler == null) return null;
    return () {
      Haptics.select();
      handler();
    };
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: _onTap,
      hapticsOnTap: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      borderRadius: BorderRadius.circular(999),
      backgroundColor: active ? skin.tintBlue : skin.bgElevated,
      child: AppText(
        label,
        style: AppTextStyle.style12SemiBold.copyWith(color: active ? skin.blue : skin.textTertiary),
      ),
    );
  }
}
