import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/chat_screen.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class SessionRouteScreen extends StatefulWidget {
  const SessionRouteScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionRouteScreen> createState() => _SessionRouteScreenState();
}

class _SessionRouteScreenState extends State<SessionRouteScreen> {
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SessionsCubit>();
    if (_lookup(cubit) == null) {
      _resolving = true;
      _resolve(cubit);
    }
  }

  Future<void> _resolve(SessionsCubit cubit) async {
    if (cubit.state is SessionsInitialState ||
        cubit.state is GetSessionsLoadingState) {
      await cubit.stream.firstWhere(
        (state) =>
            state is GetSessionsSuccessState ||
            state is GetSessionsFailureState,
      );
    } else {
      await cubit.refresh();
    }
    if (mounted) setState(() => _resolving = false);
  }

  ({String id, String? mode, String title, String? projectId})? _lookup(
    SessionsCubit cubit,
  ) {
    for (final session in cubit.sessions) {
      if (session.id == widget.sessionId) {
        return (
          id: session.id!,
          mode: session.mode,
          title: sessionTitle(session),
          projectId: session.projectId,
        );
      }
    }
    for (final orchestrator in cubit.orchestrators) {
      if (orchestrator.id == widget.sessionId) {
        return (
          id: orchestrator.id!,
          mode: orchestrator.mode,
          title: orchestrator.projectName ?? orchestrator.id!,
          projectId: orchestrator.projectId,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionsCubit, SessionsState>(
      buildWhen: (previous, current) =>
          current is GetSessionsLoadingState ||
          current is GetSessionsSuccessState ||
          current is GetSessionsFailureState,
      builder: (context, state) {
        final session = _lookup(context.read<SessionsCubit>());

        if (session?.mode == 'chat') {
          return ChatScreen(
            sessionId: session!.id,
            title: session.title,
            projectId: session.projectId,
          );
        }

        return Scaffold(
          backgroundColor: context.skin.bgBase,
          appBar: GlobalAppbar.sub(titleText: session?.title ?? 'Session'),
          body: session?.mode == 'tui'
              ? const AppEmptyState(
                  icon: Icons.terminal,
                  title: 'Terminal UI is not in this build yet',
                  message:
                      'This session runs in the agent\'s terminal interface. '
                      'Open it from the Operator desktop app until the phone can render it.',
                )
              : _resolving
              ? Center(
                  child: CircularProgressIndicator(color: context.skin.blue),
                )
              : const AppEmptyState(
                  icon: Icons.help_outline,
                  title: 'Session not found.',
                  message: 'The daemon no longer lists this session.',
                ),
        );
      },
    );
  }
}
