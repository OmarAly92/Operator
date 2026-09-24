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
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

enum SpawnOption { project, agent, account }

const String _catalogError = 'Could not reach your Operator server';

ProjectModel? _projectById(List<ProjectModel> projects, String? id) {
  if (id == null) return null;
  for (final project in projects) {
    if (project.id == id) return project;
  }
  return null;
}

RankedAgent? _agentById(List<RankedAgent> agents, String id) {
  for (final agent in agents) {
    if (agent.id == id) return agent;
  }
  return null;
}

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
          child: AppText('Done', style: AppTextStyle.style15SemiBold.copyWith(color: context.skin.accent)),
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
    detent: AppSheetDetent.large,
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
        cubit.setProject(id, kind: _projectById(projects, id)?.kind);
        AppSheet.of(context).pop();
      },
    );

AppSheetPage _agentPage(SpawnCubit cubit, Future<void> Function() onRefreshAgents) {
  final template = agentPickerPage(agents: const [], selected: '', onPicked: (_, _) {});
  return AppSheetPage(
    title: template.title,
    subtitle: template.subtitle,
    searchHint: template.searchHint,
    emptyText: template.emptyText,
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
  final template = claudeAccountPickerPage(accounts: const [], selected: '', onPicked: (_, _) {});
  return AppSheetPage(
    title: template.title,
    subtitle: template.subtitle,
    searchHint: template.searchHint,
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
          icon: Icon(Icons.refresh, size: 20, color: skin.accent),
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

  String _claudeAccountValue(SpawnCubit cubit) {
    for (final account in cubit.claudeAccounts) {
      if (account.id == cubit.claudeAccountId) return account.displayLabel;
    }
    return 'Default';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpawnCubit, SpawnState>(
      builder: (context, state) {
        final cubit = context.read<SpawnCubit>();
        final project = _projectById(projects, cubit.projectId);
        final selectedAgent = _agentById(cubit.agents, cubit.harness);

        String agentValue;
        if (selectedAgent != null) {
          agentValue = selectedAgent.label;
        } else if (state is CatalogLoadingState) {
          agentValue = 'Loading…';
        } else {
          agentValue = 'Choose an agent';
        }

        return SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.folder_outlined,
              label: 'Project',
              value: project?.name ?? 'Choose a project',
              onTap: () => onOpen(context, SpawnOption.project),
            ),
            SettingsRow(
              label: 'Agent',
              value: agentValue,
              leading: AgentLogo(harness: cubit.harness.isEmpty ? null : cubit.harness, size: 20),
              onTap: () => onOpen(context, SpawnOption.agent),
            ),
            if (cubit.harness == 'claude-code' && cubit.claudeAccounts.isNotEmpty)
              SettingsRow(
                icon: Icons.person_outline,
                label: 'Account',
                value: _claudeAccountValue(cubit),
                onTap: () => onOpen(context, SpawnOption.account),
              ),
          ],
        );
      },
    );
  }
}
