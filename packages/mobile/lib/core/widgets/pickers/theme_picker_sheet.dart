import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/theme_preference.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

Future<ThemeMode?> showThemePickerSheet(BuildContext context, {required ThemeMode selected}) {
  final skin = context.skin;
  return showModalBottomSheet<ThemeMode>(
    context: context,
    backgroundColor: skin.bgSurface,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          AppText('Theme', style: AppTextStyle.style17SemiBold),
          const VerticalSpace(4),
          AppText(
            'Applies across the app.',
            style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
            maxLines: 2,
          ),
          const VerticalSpace(8),
          for (final mode in ThemeMode.values)
            _ThemeOption(
              label: preferenceLabel(mode),
              selected: selected == mode,
              onTap: () {
                Haptics.select();
                Navigator.of(sheetContext).pop(mode);
              },
            ),
        ],
      ),
    ),
  );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(child: AppText(label, style: AppTextStyle.style15Medium)),
          if (selected) Icon(Icons.check, size: 18, color: skin.blue),
        ],
      ),
    );
  }
}
