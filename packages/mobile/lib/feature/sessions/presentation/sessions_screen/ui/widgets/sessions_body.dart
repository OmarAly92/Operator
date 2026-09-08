import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/fade_up_entrance.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/pickers/project_switcher.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/logic/sessions_filter.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_filter_chips_row.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';

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
  SessionsFilter _filter = SessionsFilter.all;

  void _selectFilter(SessionsFilter filter) {
    Haptics.select();
    setState(() => _filter = filter);
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
          return Center(child: AppExpressiveLoader(label: 'Syncing agents…'));
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

        final counts = <SessionsFilter, int>{
          SessionsFilter.all: cubit.visibleSessions.length - grouped.archived.length,
          SessionsFilter.needsYou: needsYou,
          SessionsFilter.working: working,
          SessionsFilter.mergeable: mergeable,
          SessionsFilter.archive: grouped.archived.length,
        };

        final visibleSections = grouped.sections
            .where((section) => sessionsFilterAllowsZone(_filter, section.zone))
            .toList();
        final showArchive = _filter == SessionsFilter.all || _filter == SessionsFilter.archive;
        final archiveForcedOpen = _filter == SessionsFilter.archive;
        final nothingHere = visibleSections.isEmpty && (!showArchive || grouped.archived.isEmpty);

        void openActions(SessionModel session) => showSessionActionsSheet(context, session);

        var cardIndex = 0;
        Widget buildCard(SessionModel session) {
          final entranceIndex = cardIndex++;
          return FadeUpEntrance(
            index: entranceIndex,
            child: Padding(
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
          );
        }

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
              SessionFilterChipsRow(selected: _filter, onSelect: _selectFilter, counts: counts),
              for (final section in visibleSections) ...[
                KeyedSubtree(
                  key: _sectionKeys[section.zone],
                  child: SessionSectionHeader(label: section.label, color: section.color, count: section.sessions.length),
                ),
                for (final session in section.sessions) buildCard(session),
              ],
              if (showArchive && grouped.archived.isNotEmpty) ...[
                SessionSectionHeader(
                  label: 'Archive',
                  color: skin.textFaint,
                  count: grouped.archived.length,
                  expanded: archiveForcedOpen || _archiveExpanded,
                  onTap: archiveForcedOpen
                      ? null
                      : () {
                          Haptics.tap();
                          setState(() => _archiveExpanded = !_archiveExpanded);
                        },
                ),
                if (archiveForcedOpen || _archiveExpanded)
                  for (final session in grouped.archived) buildCard(session),
              ],
              if (nothingHere)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 34, 16, 34),
                  child: AppText(
                    'Nothing here right now.',
                    style: AppTextStyle.style13p5Regular.copyWith(color: skin.textTertiary),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              if (grouped.sections.isEmpty && grouped.archived.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: AppEmptyState(
                    title: 'No agents running',
                    message: 'Spawn an agent to start work, or refresh if you expected one here.',
                    action: Column(
                      children: [
                        PrimaryButton(
                          text: 'Spawn agent',
                          onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.spawn),
                        ),
                        TextButton(
                          onPressed: () {
                            Haptics.tap();
                            cubit.refresh();
                          },
                          child: AppText(
                            'Refresh',
                            style: AppTextStyle.style13p5Medium.copyWith(color: skin.textSecondary),
                          ),
                        ),
                      ],
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
