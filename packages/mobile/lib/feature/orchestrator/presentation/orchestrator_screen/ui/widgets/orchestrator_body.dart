import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/feature/orchestrator/logic/orchestrator_view.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_card.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

OrchestratorModel? _linkFor(List<OrchestratorModel> orchestrators, String? projectId) {
  for (final orchestrator in orchestrators) {
    if (orchestrator.projectId == projectId) return orchestrator;
  }
  return null;
}

class OrchestratorBody extends StatefulWidget {
  const OrchestratorBody({super.key, required this.onOpenBoard});

  final VoidCallback onOpenBoard;

  @override
  State<OrchestratorBody> createState() => _OrchestratorBodyState();
}

class _OrchestratorBodyState extends State<OrchestratorBody> {
  String? _launchingProjectId;
  bool _launchingClean = false;

  @override
  Widget build(BuildContext context) {
    final sessionsCubit = context.read<SessionsCubit>();

    return BlocListener<OrchestratorCubit, OrchestratorLaunchState>(
      listener: (context, state) {
        if (state is LaunchLoadingState) {
          _launchingProjectId = state.projectId;
          _launchingClean = state.clean;
        }
        if (state is LaunchSuccessState) {
          sessionsCubit.refresh();
          context.showSnackBar('Orchestrator started');
          Navigator.of(context).pushNamed(
            RoutesStrings.session,
            arguments: {'sessionId': state.link.id},
          );
        }
        if (state is LaunchFailureState) {
          Haptics.error();
          if (state.chatUnavailable) {
            final projectId = _launchingProjectId;
            final clean = _launchingClean;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(chatErrorCopy(state.failure)),
                action: SnackBarAction(
                  label: 'Start Terminal UI',
                  onPressed: projectId == null
                      ? () {}
                      : () => context.read<OrchestratorCubit>().launch(projectId, clean: clean, mode: 'tui'),
                ),
              ),
            );
          } else {
            final copy = _connectionCopy(context, state.failure);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${copy.title} ${copy.message}')),
            );
          }
        }
      },
      child: BlocBuilder<SessionsCubit, SessionsState>(
        builder: (context, sessionsState) {
          final projects = sessionsCubit.projects;
          final failureState = sessionsState is GetSessionsFailureState ? sessionsState : null;
          final isConnectionFailure = projects.isEmpty && failureState != null;

          if (projects.isEmpty) {
            return isConnectionFailure
                ? _connectionFailureState(context, sessionsCubit, failureState)
                : const AppEmptyState(
                    icon: Icons.hub_outlined,
                    title: 'No projects',
                    message: 'Projects will show up here once your desktop reports one.',
                  );
          }

          return RefreshIndicator(
            onRefresh: () async {
              Haptics.tap();
              await sessionsCubit.refresh();
            },
            child: ListView(
              controller: HomeShell.controllerFor(1),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ...projects.map((project) {
                  final link = _linkFor(sessionsCubit.orchestrators, project.id);
                  final sessionId = link?.id;
                  return OrchestratorCard(
                    projectId: project.id ?? '',
                    projectName: project.name ?? project.id ?? '',
                    link: link,
                    workers: workersOf(
                      sessionsCubit.sessions,
                      project.id ?? '',
                      link,
                    ),
                    onOpenBoard: widget.onOpenBoard,
                    onOpen: sessionId == null
                        ? null
                        : () => Navigator.of(context).pushNamed(
                              RoutesStrings.session,
                              arguments: {'sessionId': sessionId},
                            ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  ConnectionErrorCopy _connectionCopy(BuildContext context, Failure failure) {
    final target = sl<ServerConfigStore>().current;
    return describeConnectionFailure(
      classifyConnectionFailure(failure.statusCode),
      host: target?.host ?? '',
      port: target?.httpPort ?? '',
      platform: Theme.of(context).platform,
    );
  }

  Widget _connectionFailureState(BuildContext context, SessionsCubit sessionsCubit, GetSessionsFailureState state) {
    final copy = _connectionCopy(context, state.failure);
    return AppEmptyState(
      icon: Icons.wifi_off,
      title: copy.title,
      message: copy.message,
      action: PrimaryButton(text: 'Retry', onPressed: sessionsCubit.refresh),
    );
  }
}
