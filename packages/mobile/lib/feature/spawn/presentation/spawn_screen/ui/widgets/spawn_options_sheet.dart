import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/pickers/agent_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/claude_account_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';
import 'package:operator_mobile/feature/spawn/logic/branch_options.dart';
import 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_option_rows.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';

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
        SpawnOption.permission => _permissionPage(cubit),
        SpawnOption.branch => _branchPage(),
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

AppSheetPage _permissionPage(SpawnCubit cubit) => AppSheetPage(
      title: 'Permission',
      subtitle: 'How much the agent asks before it acts.',
      rows: (context, _) => [
        BlocBuilder<SpawnCubit, SpawnState>(
          builder: (context, _) => SettingsGroup(
            children: [
              for (final mode in SpawnOptionValues.permissionModesFor(cubit.harness))
                SettingsRow(
                  key: ValueKey('spawn-permission-$mode'),
                  label: permissionModeLabel(mode),
                  trailing: mode == cubit.permissionMode
                      ? Icon(Icons.check_rounded, size: 18, color: context.skin.accent)
                      : const SizedBox.shrink(),
                  onTap: () {
                    cubit.setPermissionMode(mode);
                    AppSheet.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ],
    );

AppSheetPage _branchPage() => AppSheetPage(
      title: 'Branch',
      subtitle: 'Which branch the agent works on.',
      rows: (context, _) => [const _BranchPicker()],
    );

class _BranchPicker extends StatefulWidget {
  const _BranchPicker();

  @override
  State<_BranchPicker> createState() => _BranchPickerState();
}

class _BranchPickerState extends State<_BranchPicker> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(SpawnCubit cubit, {required bool worktree, String? branch}) {
    Haptics.select();
    cubit.pickBranch(worktree: worktree, branch: branch);
    AppSheet.of(context).close();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<SpawnCubit, SpawnState>(
      builder: (context, _) {
        final cubit = context.read<SpawnCubit>();
        final searchable = BranchOptions.showsSearch(cubit.branches);
        final query = searchable ? _query : '';
        final visible = BranchOptions.filter(cubit.branches, query);
        final check = Icon(Icons.check_rounded, size: 18, color: skin.accent);
        final rows = <Widget>[
          if (query.trim().isEmpty)
            SettingsRow(
              key: const ValueKey('spawn-branch-new'),
              label: kNewBranchLabel,
              trailing: cubit.useWorktree && cubit.selectedBranch == null ? check : const SizedBox.shrink(),
              onTap: () => _pick(cubit, worktree: true),
            ),
          for (final branch in visible) _branchRow(cubit, branch, check),
        ];
        final String? note = cubit.branchesLoading
            ? 'Loading branches…'
            : cubit.branchesError != null
            ? kBranchesFailedText
            : query.trim().isNotEmpty && visible.isEmpty
            ? kNoBranchMatchesText
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (searchable) ...[
              AppTextField(
                key: const ValueKey('spawn-branch-search'),
                controller: _search,
                hintText: kSearchBranchesHint,
                autocorrect: false,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
            ],
            if (rows.isNotEmpty) SettingsGroup(children: rows),
            if (note != null) AgentPickerEmpty(note),
          ],
        );
      },
    );
  }

  Widget _branchRow(SpawnCubit cubit, ProjectBranchModel branch, Widget check) {
    final name = branch.name ?? '';
    final reason = BranchOptions.busyReason(branch);
    final inFolder = branch.isMainCheckout == true;
    final selected = inFolder ? !cubit.useWorktree : cubit.useWorktree && cubit.selectedBranch == name;
    final row = SettingsRow(
      key: ValueKey('spawn-branch-$name'),
      label: name,
      subtitle: inFolder ? kProjectFolderBranchText : reason,
      trailing: selected ? check : const SizedBox.shrink(),
      onTap: reason != null
          ? null
          : inFolder
          ? () => _pick(cubit, worktree: false)
          : () => _pick(cubit, worktree: true, branch: name),
    );
    return reason == null ? row : Opacity(opacity: 0.45, child: row);
  }
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
