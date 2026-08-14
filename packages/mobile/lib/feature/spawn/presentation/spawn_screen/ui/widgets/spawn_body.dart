import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
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

const String _chatModeHint = 'Chat opens a conversation with the agent inside Operator.';
const String _tuiModeHint = "Terminal UI runs the agent's own interface inside a session tab.";
const String _noChatAgentWarning =
    'No agent supports Chat mode yet. Install or authorize a Chat-capable agent, or switch to Terminal UI.';

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
      onRefresh: _cubit.refreshCatalog,
      error: state is CatalogFailureState ? 'Could not reach your Operator server' : null,
    );
    if (chosen != null && context.mounted) _cubit.setHarness(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocConsumer<SpawnCubit, SpawnState>(
      listener: (context, state) {
        if (state is SpawnSuccessState) {
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
        final catalogLoaded = state is! CatalogLoadingState && state is! SpawnInitialState;
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

        final showNoChatAgentWarning = _cubit.mode == 'chat' && _cubit.agents.isEmpty && catalogLoaded;

        String? errorText;
        if (state is SpawnValidationFailureState) errorText = state.message;
        if (state is SpawnFailureState) {
          errorText = state.chatUnavailable ? chatErrorCopy(state.failure) : state.failure.message;
        }

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
              AppText(
                'INTERFACE',
                style: AppTextStyle.style11Bold.copyWith(color: skin.textTertiary, letterSpacing: 1.2),
              ),
              const VerticalSpace(8),
              Semantics(
                container: true,
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeOption(
                        title: 'Chat',
                        subtitle: 'Native conversation',
                        selected: _cubit.mode == 'chat',
                        onTap: () => setState(() => _cubit.setMode('chat')),
                      ),
                    ),
                    const HorizontalSpace(10),
                    Expanded(
                      child: _ModeOption(
                        title: 'Terminal UI',
                        subtitle: "Agent's own TUI",
                        selected: _cubit.mode == 'tui',
                        onTap: () => setState(() => _cubit.setMode('tui')),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalSpace(8),
              AppText(
                _cubit.mode == 'chat' ? _chatModeHint : _tuiModeHint,
                style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                maxLines: 2,
              ),
              if (showNoChatAgentWarning) ...[
                const VerticalSpace(8),
                AppText(
                  _noChatAgentWarning,
                  style: AppTextStyle.style12Regular.copyWith(color: skin.amber),
                  maxLines: 3,
                ),
              ],
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
              if (state is SpawnFailureState && state.chatUnavailable) ...[
                const VerticalSpace(8),
                TextButton(
                  onPressed: () => setState(() => _cubit.setMode('tui')),
                  child: AppText(
                    'Create as Terminal UI instead',
                    style: AppTextStyle.style13SemiBold.copyWith(color: skin.blue),
                  ),
                ),
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

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.title, required this.subtitle, required this.selected, required this.onTap});

  final String title;
  final String subtitle;
  final bool selected;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? skin.tintBlue : skin.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? skin.blue : skin.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              title,
              style: AppTextStyle.style15SemiBold.copyWith(color: selected ? skin.blue : skin.textPrimary),
            ),
            const VerticalSpace(2),
            AppText(subtitle, style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary), maxLines: 2),
          ],
        ),
      ),
    );
  }
}
