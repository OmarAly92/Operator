import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/pickers/agent_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/claude_account_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_option_rows.dart';

export 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart' show SpawnOption;

const String _catalogError = 'Could not reach your Operator server';

Future<void> showSpawnOptionsSheet(
  BuildContext context, {
  required SpawnCubit cubit,
  required List<ProjectModel> projects,
  required SpawnOption open,
  required Future<void> Function() onRefreshAgents,
}) {
  AppSheetPage pageFor(SpawnOption option) => switch (option) {
        SpawnOption.project => _projectPage(cubit, projects),
        SpawnOption.agent => _agentPage(cubit, onRefreshAgents),
        SpawnOption.account => _accountPage(cubit),
      };

  final root = AppSheetPage(
    title: 'Spawn options',
    actions: [
      Builder(
        builder: (context) => TextButton(
          onPressed: () => AppSheet.of(context).close(),
          child: AppText('Done', style: AppTextStyle.style15SemiBold.copyWith(color: context.skin.accentText)),
        ),
      ),
    ],
    rows: (context, query) => [
      _SpawnOptionsRows(projects: projects, onOpen: (context, option) => AppSheet.of(context).push(pageFor(option))),
    ],
  );

  return showAppSheet<void>(
    context: context,
    page: root,
    pushed: [pageFor(open)],
    detent: AppSheetDetent.fit,
    scope: (sheetContext, sheet) => BlocProvider<SpawnCubit>.value(value: cubit, child: sheet),
  );
}

AppSheetPage _projectPage(SpawnCubit cubit, List<ProjectModel> projects) => projectPickerPage(
      projects: projects,
      selected: cubit.projectId ?? '',
      includeAll: false,
      title: 'Project',
      subtitle: 'Where this agent gets its workspace.',
      onPicked: (context, id) {
        cubit.setProject(id, kind: SpawnOptionValues.projectById(projects, id)?.kind);
        AppSheet.of(context).pop();
      },
    );

AppSheetPage _agentPage(SpawnCubit cubit, Future<void> Function() onRefreshAgents) {
  return AppSheetPage(
    title: kAgentPickerTitle,
    subtitle: kAgentPickerSubtitle,
    searchHint: kAgentPickerSearchHint,
    actions: [_RefreshAgentsAction(onRefresh: onRefreshAgents)],
    rows: (context, query) => [
      BlocBuilder<SpawnCubit, SpawnState>(
        builder: (context, state) {
          final page = agentPickerPage(
            agents: cubit.agents,
            selected: cubit.harness,
            error: state is CatalogFailureState ? _catalogError : null,
            onPicked: (context, id) {
              cubit.setHarness(id);
              AppSheet.of(context).pop();
            },
          );
          final rows = page.rows(context, query);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows.isEmpty ? [AgentPickerEmpty(query.isEmpty ? kNoAgentsText : 'No matches')] : rows,
          );
        },
      ),
    ],
  );
}

AppSheetPage _accountPage(SpawnCubit cubit) {
  return AppSheetPage(
    title: kClaudeAccountPickerTitle,
    subtitle: kClaudeAccountPickerSubtitle,
    searchHint: kClaudeAccountPickerSearchHint,
    rows: (context, query) => [
      BlocBuilder<SpawnCubit, SpawnState>(
        builder: (context, state) {
          final rows = claudeAccountPickerPage(
            accounts: cubit.claudeAccounts,
            selected: cubit.claudeAccountId,
            onPicked: (context, id) {
              cubit.setClaudeAccount(id);
              AppSheet.of(context).pop();
            },
          ).rows(context, query);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows.isEmpty && query.isNotEmpty ? const [AgentPickerEmpty('No matches')] : rows,
          );
        },
      ),
    ],
  );
}

class _RefreshAgentsAction extends StatelessWidget {
  const _RefreshAgentsAction({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<SpawnCubit, SpawnState>(
      builder: (context, state) {
        if (state is CatalogLoadingState) {
          return const SizedBox(width: 16, height: 16, child: AppLoader(strokeWidth: 2));
        }
        return IconButton(
          icon: Icon(Icons.refresh, size: 20, color: skin.accentText),
          tooltip: 'Refresh agents',
          onPressed: () {
            Haptics.tap();
            onRefresh();
          },
        );
      },
    );
  }
}

class _SpawnOptionsRows extends StatelessWidget {
  const _SpawnOptionsRows({required this.projects, required this.onOpen});

  final List<ProjectModel> projects;
  final void Function(BuildContext context, SpawnOption option) onOpen;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpawnCubit, SpawnState>(
      builder: (context, state) => SettingsGroup(
        children: spawnOptionRows(
          cubit: context.read<SpawnCubit>(),
          state: state,
          projects: projects,
          onOpen: (option) => onOpen(context, option),
        ),
      ),
    );
  }
}
