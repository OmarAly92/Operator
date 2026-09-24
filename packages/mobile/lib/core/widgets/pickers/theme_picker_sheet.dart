import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/theme_preference.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

Future<ThemeMode?> showThemePickerSheet(BuildContext context, {required ThemeMode selected}) {
  return showAppSheet<ThemeMode>(
    context: context,
    page: AppSheetPage(
      title: 'Theme',
      subtitle: 'Applies across the app.',
      rows: (context, query) => [
        for (final mode in ThemeMode.values)
          _ThemeOption(
            label: preferenceLabel(mode),
            selected: selected == mode,
            onTap: () {
              Haptics.select();
              Navigator.of(context).pop(mode);
            },
          ),
      ],
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
      hapticsOnTap: false,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(child: AppText(label, style: AppTextStyle.style15Medium)),
          if (selected) Icon(Icons.check, size: 18, color: skin.accent),
        ],
      ),
    );
  }
}
