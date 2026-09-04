import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/agent_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

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

class SpawnBody extends StatefulWidget {
  const SpawnBody({super.key});

  @override
  State<SpawnBody> createState() => _SpawnBodyState();
}

class _SpawnBodyState extends State<SpawnBody> {
  late final SpawnCubit _cubit;
  late final SessionsCubit _sessionsCubit;
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<SpawnCubit>();
    _sessionsCubit = sl<SessionsCubit>();
    _nameController = TextEditingController(text: _cubit.name);
    _promptController = TextEditingController(text: _cubit.prompt);

    final activeProjectId = _sessionsCubit.activeProjectId;
    if (activeProjectId != kAllProjects) {
      _cubit.setProject(activeProjectId);
    } else if (_sessionsCubit.projects.length == 1) {
      _cubit.setProject(_sessionsCubit.projects.first.id);
    }
    _cubit.loadCatalog();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _openProjectPicker(BuildContext context) async {
    final chosen = await showProjectPickerSheet(
      context,
      projects: _sessionsCubit.projects,
      selected: _cubit.projectId ?? '',
      includeAll: false,
      title: 'Project',
      subtitle: 'Where this agent gets its workspace.',
    );
    if (chosen != null && context.mounted) _cubit.setProject(chosen);
  }

  Future<void> _openAgentPicker(BuildContext context, SpawnState state) async {
    final chosen = await showAgentPickerSheet(
      context,
      agents: _cubit.agents,
      selected: _cubit.harness,
      onRefresh: _refreshCatalog,
      error: state is CatalogFailureState ? 'Could not reach your Operator server' : null,
    );
    if (chosen != null && context.mounted) _cubit.setHarness(chosen);
  }

  Future<void> _refreshCatalog() async {
    final resolved = _cubit.stream.firstWhere((s) => s is CatalogReadyState || s is CatalogFailureState);
    await _cubit.refreshCatalog();
    final state = await resolved;
    if (state is CatalogReadyState) Haptics.success();
    if (state is CatalogFailureState) Haptics.error();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocConsumer<SpawnCubit, SpawnState>(
      listener: (context, state) {
        if (state is SpawnValidationFailureState) {
          Haptics.error();
        }
        if (state is SpawnFailureState) {
          Haptics.error();
        }
        if (state is SpawnSuccessState) {
          Haptics.success();
          _sessionsCubit.refresh();
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
          navigator.pushNamed(
            RoutesStrings.session,
            arguments: {'sessionId': state.session.id},
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text('Spawned ${state.session.displayName ?? state.session.issueId ?? 'agent'}'),
            ),
          );
        }
      },
      builder: (context, state) {
        final project = _projectById(_sessionsCubit.projects, _cubit.projectId);
        final selectedAgent = _agentById(_cubit.agents, _cubit.harness);

        String agentValue;
        if (selectedAgent != null) {
          agentValue = selectedAgent.label;
        } else if (state is CatalogLoadingState) {
          agentValue = 'Loading…';
        } else {
          agentValue = 'Choose an agent';
        }

        String? errorText;
        if (state is SpawnValidationFailureState) errorText = state.message;
        if (state is SpawnFailureState) errorText = state.failure.message;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Spawn a worker agent. It gets its own isolated workspace, then starts on the task you give it.',
                style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                maxLines: 3,
              ),
              const VerticalSpace(16),
              SettingsGroup(
                footer: 'Agent availability is cached.',
                children: [
                  SettingsRow(
                    icon: Icons.folder_outlined,
                    label: 'Project',
                    value: project?.name ?? 'Choose a project',
                    onTap: () => _openProjectPicker(context),
                  ),
                  SettingsRow(
                    label: 'Agent',
                    value: agentValue,
                    leading: AgentLogo(harness: _cubit.harness.isEmpty ? null : _cubit.harness, size: 20),
                    onTap: () => _openAgentPicker(context, state),
                  ),
                ],
              ),
              const VerticalSpace(20),
              AppTextField(
                controller: _nameController,
                label: 'NAME',
                hintText: 'Short title for this task',
                onChanged: (value) => _cubit.name = value,
              ),
              const VerticalSpace(16),
              AppTextField(
                controller: _promptController,
                label: 'TASK',
                hintText: 'What should this agent do?',
                onChanged: (value) => _cubit.prompt = value,
              ),
              if (errorText != null) ...[
                const VerticalSpace(12),
                AppText(errorText, style: AppTextStyle.style13Regular.copyWith(color: skin.red), maxLines: 3),
              ],
              const VerticalSpace(16),
              PrimaryButton.expand(
                text: 'Spawn agent',
                isLoading: state is SpawnLoadingState,
                onPressed: _cubit.submit,
              ),
              const VerticalSpace(8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
