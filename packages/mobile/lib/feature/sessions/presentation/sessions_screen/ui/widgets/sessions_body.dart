import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_stats_row.dart';

class SessionsBody extends StatelessWidget {
  const SessionsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SessionsCubit>();
    final skin = context.skin;

    return BlocBuilder<SessionsCubit, SessionsState>(
      buildWhen: (previous, current) =>
          current is GetSessionsLoadingState || current is GetSessionsSuccessState || current is GetSessionsFailureState,
      builder: (context, state) {
        if (cubit.visibleSessions.isEmpty && state is GetSessionsLoadingState) {
          return const AppLoader.center();
        }
        if (cubit.visibleSessions.isEmpty && state is GetSessionsFailureState) {
          return AppErrorWidget(failure: state.failure, onPressed: cubit.refresh);
        }

        final grouped = groupSessions(skin, cubit.visibleSessions);
        var working = 0;
        var needsYou = 0;
        var mergeable = 0;
        for (final session in cubit.visibleSessions) {
          switch (attentionOf(session)) {
            case AttentionLevel.working:
              working++;
            case AttentionLevel.respond:
              needsYou++;
            case AttentionLevel.merge:
              mergeable++;
            case AttentionLevel.review:
            case AttentionLevel.pending:
            case AttentionLevel.done:
              break;
          }
        }

        void openActions(SessionModel session) => showSessionActionsSheet(context, session);

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              SessionsStatsRow(working: working, needsYou: needsYou, mergeable: mergeable),
              for (final section in grouped.sections) ...[
                SessionSectionHeader(label: section.label, color: section.color, count: section.sessions.length),
                for (final session in section.sessions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SessionCard(
                      session: session,
                      showProject: true,
                      onTap: () {},
                      onLongPress: () => openActions(session),
                    ),
                  ),
              ],
              if (grouped.archived.isNotEmpty) ...[
                SessionSectionHeader(label: 'Archive', color: skin.textFaint, count: grouped.archived.length),
                for (final session in grouped.archived)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SessionCard(
                      session: session,
                      showProject: true,
                      onTap: () {},
                      onLongPress: () => openActions(session),
                    ),
                  ),
              ],
              if (grouped.sections.isEmpty && grouped.archived.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: AppText('No active agents')),
                ),
            ],
          ),
        );
      },
    );
  }
}
