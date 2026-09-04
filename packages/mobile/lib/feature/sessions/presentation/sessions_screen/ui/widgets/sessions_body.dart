import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/pickers/project_switcher.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_stats_row.dart';

class SessionsBody extends StatefulWidget {
  const SessionsBody({super.key});

  @override
  State<SessionsBody> createState() => _SessionsBodyState();
}

class _SessionsBodyState extends State<SessionsBody> {
  // Keyed by zone rather than by rendered section: a zone that is empty on this
  // tick still owns its key, so a section appearing later reuses the same
  // element instead of being re-inflated.
  final Map<BoardZone, GlobalKey> _sectionKeys = {
    for (final zone in BoardZone.values) zone: GlobalKey(),
  };

  bool _archiveExpanded = false;

  void _jumpTo(BoardZone zone) {
    final sectionContext = _sectionKeys[zone]?.currentContext;
    if (sectionContext == null) return;
    Haptics.select();
    Scrollable.ensureVisible(sectionContext, duration: const Duration(milliseconds: 200));
  }

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
          onRefresh: () async {
            Haptics.tap();
            await cubit.refresh();
          },
          child: ListView(
            controller: HomeShell.controllerFor(0),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const ProjectSwitcher(),
              SessionsStatsRow(
                working: working,
                needsYou: needsYou,
                mergeable: mergeable,
                onTapWorking: () => _jumpTo(BoardZone.working),
                onTapNeedsYou: () => _jumpTo(BoardZone.action),
                onTapMergeable: () => _jumpTo(BoardZone.merge),
              ),
              for (final section in grouped.sections) ...[
                KeyedSubtree(
                  key: _sectionKeys[section.zone],
                  child: SessionSectionHeader(label: section.label, color: section.color, count: section.sessions.length),
                ),
                for (final session in section.sessions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SessionCard(
                      session: session,
                      showProject: true,
                      onTap: () => Navigator.of(context).pushNamed(
                        RoutesStrings.session,
                        arguments: {'sessionId': session.id},
                      ),
                      onLongPress: () => openActions(session),
                    ),
                  ),
              ],
              if (grouped.archived.isNotEmpty) ...[
                SessionSectionHeader(
                  label: 'Archive',
                  color: skin.textFaint,
                  count: grouped.archived.length,
                  expanded: _archiveExpanded,
                  onTap: () {
                    Haptics.tap();
                    setState(() => _archiveExpanded = !_archiveExpanded);
                  },
                ),
                if (_archiveExpanded)
                  for (final session in grouped.archived)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: SessionCard(
                        session: session,
                        showProject: true,
                        onTap: () => Navigator.of(context).pushNamed(
                          RoutesStrings.session,
                          arguments: {'sessionId': session.id},
                        ),
                        onLongPress: () => openActions(session),
                      ),
                    ),
              ],
              if (grouped.sections.isEmpty && grouped.archived.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: AppEmptyState(
                    icon: Icons.auto_awesome_motion_outlined,
                    title: 'No active agents',
                    message: 'Spawn a worker agent to get started.',
                    action: PrimaryButton(
                      text: 'New agent',
                      onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.spawn),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
