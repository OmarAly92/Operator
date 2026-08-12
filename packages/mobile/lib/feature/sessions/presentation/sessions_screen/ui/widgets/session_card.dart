import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.showProject,
    required this.onTap,
    required this.onLongPress,
  });

  final SessionModel session;
  final bool showProject;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = statusVisual(skin, session.status);
    final title = sessionTitle(session);
    final branch = showBranch(session.branch, title) ? session.branch : null;
    final issue = trackerIssueId(session.issueId);
    final prs = prLine(session);
    final when = relativeTime(session.updatedAt);

    return AppContainer(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AgentLogo(harness: session.harness, size: 20),
                const HorizontalSpace(9),
                Expanded(child: AppText(title, style: AppTextStyle.style15SemiBold, maxLines: 2)),
                if (showProject && session.projectId != null)
                  AppText(session.projectId!, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ),
            if (branch != null || issue != null) ...[
              const VerticalSpace(6),
              Padding(
                padding: const EdgeInsets.only(left: 29),
                child: Row(
                  children: [
                    if (branch != null)
                      Expanded(
                        child: AppText(branch, style: AppTextStyle.mono11Regular.copyWith(color: skin.textFaint)),
                      ),
                    if (issue != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: skin.tintBlue, borderRadius: BorderRadius.circular(5)),
                        child: AppText(issue, style: AppTextStyle.mono10Regular.copyWith(color: skin.blue)),
                      ),
                  ],
                ),
              ),
            ],
            const VerticalSpace(10),
            Container(height: 1, color: skin.borderSubtle),
            const VerticalSpace(8),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle),
                ),
                const HorizontalSpace(6),
                Expanded(
                  child: AppText(visual.label, style: AppTextStyle.style12SemiBold.copyWith(color: visual.color)),
                ),
                if (when.isNotEmpty)
                  AppText(when, style: AppTextStyle.mono11Regular.copyWith(color: skin.textFaint)),
              ],
            ),
            if (prs != null) ...[
              const VerticalSpace(5),
              AppText(prs.text, style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
