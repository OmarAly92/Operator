import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_pill.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/project_switcher.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

bool _inBucket(PrFilter filter, PrLifecycle life) {
  if (filter == PrFilter.all) return true;
  if (filter == PrFilter.open) return life == PrLifecycle.open || life == PrLifecycle.draft;
  return life == PrLifecycle.merged;
}

class PullRequestsBody extends StatelessWidget {
  const PullRequestsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionsCubit = context.read<SessionsCubit>();
    final prCubit = context.read<PullRequestCubit>();

    return BlocBuilder<SessionsCubit, SessionsState>(
      builder: (context, sessionsState) {
        return BlocBuilder<PullRequestCubit, PullRequestState>(
          builder: (context, prState) {
            final entries = collectPrs(sessionsCubit.visibleSessions);
            final filtered = entries.where((e) => _inBucket(prCubit.filter, prLifecycleOf(e.pr))).toList()
              ..sort((a, b) => comparePrs(a.pr, b.pr));
            final sessionIds = {for (final entry in filtered) entry.session.id}.whereType<String>().toList();

            WidgetsBinding.instance.addPostFrameCallback((_) => prCubit.load(sessionIds));

            var openCount = 0;
            var mergedCount = 0;
            for (final entry in entries) {
              final life = prLifecycleOf(entry.pr);
              if (life == PrLifecycle.open || life == PrLifecycle.draft) openCount++;
              if (life == PrLifecycle.merged) mergedCount++;
            }
            final allCount = entries.length;

            Future<void> onRefresh() => Future.wait([prCubit.reload(sessionIds), sessionsCubit.refresh()]);

            final noCache = sessionsCubit.visibleSessions.isEmpty;
            final failureState = sessionsState is GetSessionsFailureState ? sessionsState : null;
            final isConnectionFailure = filtered.isEmpty && failureState != null && noCache;

            return RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  const ProjectSwitcher(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        AppPill(
                          label: 'Open $openCount',
                          active: prCubit.filter == PrFilter.open,
                          onTap: () => prCubit.setFilter(PrFilter.open),
                        ),
                        const SizedBox(width: 8),
                        AppPill(
                          label: 'Merged $mergedCount',
                          active: prCubit.filter == PrFilter.merged,
                          onTap: () => prCubit.setFilter(PrFilter.merged),
                        ),
                        const SizedBox(width: 8),
                        AppPill(
                          label: 'All $allCount',
                          active: prCubit.filter == PrFilter.all,
                          onTap: () => prCubit.setFilter(PrFilter.all),
                        ),
                      ],
                    ),
                  ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: isConnectionFailure
                          ? _connectionFailureState(context, sessionsCubit, failureState)
                          : const AppEmptyState(
                              icon: Icons.merge_outlined,
                              title: 'No pull requests',
                              message: 'Pull requests opened from your sessions will show up here.',
                            ),
                    )
                  else
                    for (final entry in filtered)
                      PrCard(
                        pr: entry.pr,
                        session: entry.session,
                        summary: prCubit.summaryFor(entry.session.id ?? '', entry.pr.number ?? 0),
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _connectionFailureState(BuildContext context, SessionsCubit sessionsCubit, GetSessionsFailureState state) {
    final target = sl<ServerConfigStore>().current;
    final copy = describeConnectionFailure(
      classifyConnectionFailure(state.failure.statusCode),
      host: target?.host ?? '',
      port: target?.httpPort ?? '',
      platform: Theme.of(context).platform,
    );
    return AppEmptyState(
      icon: Icons.wifi_off,
      title: copy.title,
      message: copy.message,
      action: PrimaryButton(text: 'Retry', onPressed: sessionsCubit.refresh),
    );
  }
}
