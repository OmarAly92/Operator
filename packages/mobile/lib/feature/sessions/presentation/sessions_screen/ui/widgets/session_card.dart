import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/main_widgets/status_dot.dart';
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
    final isInPlace = session.workspaceMode == 'in_place';
    final rawPath = session.workspacePath;
    final location = isInPlace
        ? (rawPath != null && rawPath.isNotEmpty ? rawPath : null)
        : _worktreeDirName(rawPath);
    final showLocation = branch != null || location != null;
    final project = showProject ? session.projectId : null;
    final issue = trackerIssueId(session.issueId);
    final prs = prLine(session);
    final when = relativeTime(session.updatedAt);

    return AppContainer(
      onTap: onTap,
      pressScale: true,
      padding: const EdgeInsets.all(13),
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      border: Border.all(color: skin.borderDefault),
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AgentLogo(harness: session.harness, size: 20),
                const HorizontalSpace(9),
                AppText(
                  title,
                  style: AppTextStyle.style15SemiBold,
                  maxLines: 2,
                ),
                const HorizontalSpace(9),
                if (project != null) ...[
                  Expanded(
                    child: AppText(
                      project,
                      style: AppTextStyle.mono11Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                  decoration: BoxDecoration(
                    color: statusChipTint(skin, visual.color),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusPill,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(
                        color: visual.color,
                        size: 7,
                        breathing: visual.breathing,
                      ),
                      const HorizontalSpace(6),
                      AppText(
                        visual.label,
                        style: AppTextStyle.style11p5SemiBold.copyWith(
                          color: visual.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (project != null ||
                showLocation ||
                issue != null ||
                when.isNotEmpty) ...[
              const VerticalSpace(7),
              Padding(
                padding: const EdgeInsets.only(left: 29),
                child: Row(
                  children: [
                    if (showLocation)
                      if (branch != null) ...[
                        Container(
                          padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                          decoration: BoxDecoration(
                            color: skin.bgColumn,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusPill,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.call_split, size: 12, color: skin.green),
                              const HorizontalSpace(4),
                              AppText(
                                branch,
                                style: AppTextStyle.mono11Regular.copyWith(
                                  color: skin.green,
                                ),
                              ),

                              if (when.isNotEmpty) ...[
                                const HorizontalSpace(6),
                                AppText(
                                  when,
                                  style: AppTextStyle.mono11Regular.copyWith(
                                    color: skin.green,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    if (issue != null) ...[
                      const HorizontalSpace(6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: skin.tintBlue,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: AppText(
                          issue,
                          style: AppTextStyle.mono10Regular.copyWith(
                            color: skin.blue,
                          ),
                        ),
                      ),
                    ],

                  ],
                ),
              ),
            ],
            VerticalSpace(3),
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  if (location != null) ...[
                    if (branch != null) const HorizontalSpace(6),
                    if (isInPlace) ...[
                      Icon(
                        Icons.folder_outlined,
                        size: 12,
                        color: skin.textFaint,
                      ),
                      const HorizontalSpace(4),
                    ],
                    Expanded(
                      child: AppText(
                        location,
                        maxLines: 2,
                        style: AppTextStyle.mono11Regular.copyWith(
                          color: skin.textFaint,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (prs != null) ...[
              const VerticalSpace(9),
              Container(height: 1, color: skin.borderSubtle),
              const VerticalSpace(9),
              Row(
                children: [
                  Icon(Icons.call_merge, size: 14, color: skin.green),
                  const HorizontalSpace(6),
                  Expanded(
                    child: AppText(
                      prs.text,
                      style: AppTextStyle.mono11Regular.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _worktreeDirName(String? workspacePath) {
  if (workspacePath == null || workspacePath.isEmpty) return null;
  final segments = workspacePath.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? null : segments.last;
}
