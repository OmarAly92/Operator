import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/picker_filter.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

AppSheetPage projectPickerPage({
  required List<ProjectModel> projects,
  required String selected,
  required void Function(BuildContext context, String id) onPicked,
  bool includeAll = true,
  String title = 'Active project',
  String subtitle = 'Scopes the Agents and PRs tabs.',
}) {
  return AppSheetPage(
    title: title,
    subtitle: subtitle,
    searchHint: 'Search projects',
    emptyText: 'No projects yet. Add one from the Operator dashboard on your computer.',
    rows: (context, query) => [
      if (includeAll && query.isEmpty && projects.isNotEmpty)
        _ProjectOption(
          label: 'All projects',
          icon: Icons.layers_outlined,
          selected: selected == kAllProjects,
          onTap: () {
            Haptics.select();
            onPicked(context, kAllProjects);
          },
        ),
      for (final project in projects)
        if (PickerFilter.matches(query, [project.name, project.id, project.sessionPrefix]))
          _ProjectOption(
            label: project.name ?? project.id ?? '',
            hint: project.sessionPrefix,
            icon: Icons.folder_outlined,
            selected: selected == project.id,
            onTap: () {
              Haptics.select();
              final id = project.id;
              if (id == null) {
                Navigator.of(context).pop();
              } else {
                onPicked(context, id);
              }
            },
          ),
    ],
  );
}

Future<String?> showProjectPickerSheet(
  BuildContext context, {
  required List<ProjectModel> projects,
  required String selected,
  bool includeAll = true,
  String title = 'Active project',
  String subtitle = 'Scopes the Agents and PRs tabs.',
}) {
  return showAppSheet<String>(
    context: context,
    page: projectPickerPage(
      projects: projects,
      selected: selected,
      includeAll: includeAll,
      title: title,
      subtitle: subtitle,
      onPicked: (context, id) => Navigator.of(context).pop(id),
    ),
    detent: AppSheetDetent.large,
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
      hapticsOnTap: false,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: selected ? skin.accentText : skin.textTertiary),
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
          if (selected) Icon(Icons.check, size: 18, color: skin.accentText),
        ],
      ),
    );
  }
}
