import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

Future<String?> showProjectPickerSheet(
  BuildContext context, {
  required List<ProjectModel> projects,
  required String selected,
  bool includeAll = true,
  String title = 'Active project',
  String subtitle = 'Scopes the Agents and PRs tabs.',
}) {
  final skin = context.skin;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: skin.bgSurface,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          AppText(title, style: AppTextStyle.style17SemiBold),
          const VerticalSpace(4),
          AppText(subtitle, style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary), maxLines: 2),
          const VerticalSpace(8),
          if (includeAll)
            _ProjectOption(
              label: 'All projects',
              icon: Icons.layers_outlined,
              selected: selected == kAllProjects,
              onTap: () {
                Haptics.select();
                Navigator.of(sheetContext).pop(kAllProjects);
              },
            ),
          for (final project in projects)
            _ProjectOption(
              label: project.name ?? project.id ?? '',
              hint: project.sessionPrefix,
              icon: Icons.folder_outlined,
              selected: selected == project.id,
              onTap: () {
                Haptics.select();
                Navigator.of(sheetContext).pop(project.id);
              },
            ),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: AppText(
                'No projects yet. Add one from the Operator dashboard on your computer.',
                style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                maxLines: 3,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProjectOption extends StatelessWidget {
  const _ProjectOption({required this.label, required this.icon, required this.selected, required this.onTap, this.hint});

  final String label;
  final IconData icon;
  final bool selected;
  final String? hint;
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
          Icon(icon, size: 18, color: selected ? skin.blue : skin.textTertiary),
          const HorizontalSpace(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(label, style: AppTextStyle.style15Medium),
                if (hint != null)
                  AppText(hint!, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 18, color: skin.blue),
        ],
      ),
    );
  }
}
