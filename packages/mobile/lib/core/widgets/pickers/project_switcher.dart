import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<SessionsCubit>();
    // A narrowed filter always shows its control, even with one project: the
    // filter is persisted, so hiding the control strands the board on a project
    // the user cannot see or leave.
    if (cubit.projects.length <= 1 && cubit.activeProjectId == kAllProjects) {
      return const SizedBox.shrink();
    }

    final skin = context.skin;
    String activeName = 'All projects';
    if (cubit.activeProjectId != kAllProjects) {
      activeName = cubit.activeProjectId;
      for (final project in cubit.projects) {
        if (project.id == cubit.activeProjectId) {
          activeName = project.name ?? project.id ?? cubit.activeProjectId;
          break;
        }
      }
    }

    Future<void> openPicker() async {
      final result = await showProjectPickerSheet(context, projects: cubit.projects, selected: cubit.activeProjectId);
      if (result != null && context.mounted) {
        cubit.setActiveProject(result);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppText('PROJECTS', style: AppTextStyle.style13Bold.copyWith(color: skin.textSecondary, letterSpacing: 0.8)),
          AppInkWell(
            onTap: openPicker,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(activeName, style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary)),
                const HorizontalSpace(4),
                Icon(Icons.expand_more, size: 18, color: skin.textTertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
