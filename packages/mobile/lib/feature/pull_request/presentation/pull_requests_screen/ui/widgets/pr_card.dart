import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/short_label.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/logic/open_github.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

const int _projectLabelMax = 12;

class PrCard extends StatelessWidget {
  const PrCard({super.key, required this.pr, required this.session, this.summary});

  final SessionPrModel pr;
  final SessionModel session;
  final SessionPrSummaryModel? summary;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final richSummary = summary;

    final state = richSummary != null
        ? stateVisualOf(skin, prLifecycleFromName(richSummary.state))
        : prStateVisual(skin, pr);

    final rawTitle = richSummary?.title?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : prTitle(pr, sessionTitle(session));

    final atoms = richSummary != null ? prStatusAtoms(richSummary) : [prSummaryLine(pr)];
    final blocker = richSummary != null ? prBlockerLine(richSummary) : null;

    final changedFiles = richSummary?.changedFiles ?? 0;
    final additions = richSummary?.additions ?? 0;
    final deletions = richSummary?.deletions ?? 0;
    final hasDiff = richSummary != null && (changedFiles > 0 || additions > 0 || deletions > 0);

    final meta = richSummary == null
        ? null
        : [
            [richSummary.sourceBranch, richSummary.targetBranch].whereType<String>().join(' → '),
            richSummary.author,
          ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');

    return AppContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.merge_outlined, size: 16, color: state.color),
              const HorizontalSpace(6),
              AppText('#${pr.number}', style: AppTextStyle.mono12Bold),
              const HorizontalSpace(6),
              AppText(state.label.name, style: AppTextStyle.style12SemiBold.copyWith(color: state.color)),
              const Spacer(),
              AppText(
                shortLabel(richSummary?.repo ?? session.projectId ?? '', max: _projectLabelMax),
                style: AppTextStyle.mono11Regular,
              ),
            ],
          ),
          const VerticalSpace(6),
          AppText(title, style: AppTextStyle.style15Medium, maxLines: 2),
          if (meta != null && meta.isNotEmpty) ...[
            const VerticalSpace(4),
            AppText(meta, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
          ],
          if (hasDiff) ...[
            const VerticalSpace(6),
            Row(
              children: [
                AppText(
                  '$changedFiles ${changedFiles == 1 ? 'file' : 'files'}',
                  style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                ),
                const HorizontalSpace(8),
                AppText('+$additions', style: AppTextStyle.mono11Regular.copyWith(color: skin.green)),
                const HorizontalSpace(8),
                AppText('−$deletions', style: AppTextStyle.mono11Regular.copyWith(color: skin.red)),
              ],
            ),
          ],
          const VerticalSpace(8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < atoms.length; i++) ...[
                      if (i > 0) AppText('·', style: AppTextStyle.style12SemiBold.copyWith(color: skin.textTertiary)),
                      AppText(
                        atoms[i].text,
                        style: AppTextStyle.style12SemiBold.copyWith(color: toneColor(skin, atoms[i].tone)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open in GitHub',
                onPressed: () => openGitHub(richSummary?.htmlUrl ?? richSummary?.url ?? pr.url ?? ''),
              ),
            ],
          ),
          if (richSummary != null && blocker != null) ...[
            const VerticalSpace(4),
            AppText(
              blocker,
              style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}
