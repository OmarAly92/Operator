import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

List<Widget> spawnOptionRows({
  required SpawnCubit cubit,
  required SpawnState state,
  required List<ProjectModel> projects,
  required void Function(SpawnOption option) onOpen,
}) {
  return [
    SettingsRow(
      icon: Icons.folder_outlined,
      label: 'Project',
      value: SpawnOptionValues.projectValue(projects, cubit.projectId),
      onTap: () => onOpen(SpawnOption.project),
    ),
    SettingsRow(
      icon: Icons.smart_toy_outlined,
      label: 'Agent',
      value: SpawnOptionValues.agentValue(cubit.agents, cubit.harness, loading: state is CatalogLoadingState),
      leading: AgentLogo(harness: cubit.harness.isEmpty ? null : cubit.harness, size: 20),
      onTap: () => onOpen(SpawnOption.agent),
    ),
    if (SpawnOptionValues.showsAccount(cubit.harness, cubit.claudeAccounts))
      SettingsRow(
        icon: Icons.person_outline,
        label: 'Account',
        value: SpawnOptionValues.accountValue(cubit.claudeAccounts, cubit.claudeAccountId),
        onTap: () => onOpen(SpawnOption.account),
      ),
    SettingsRow(
      icon: Icons.shield_outlined,
      label: 'Permission',
      value: SpawnOptionValues.permissionValue(cubit.permissionMode),
      onTap: () => onOpen(SpawnOption.permission),
    ),
  ];
}
