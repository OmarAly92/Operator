import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
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

String _lifecycleLabel(PrLifecycle life) {
  final name = life.name;
  return name[0].toUpperCase() + name.substring(1);
}

class PrCard extends StatefulWidget {
  const PrCard({
    super.key,
    required this.pr,
    required this.session,
    this.summary,
    this.onOpenSession,
    this.index = 0,
  });

  final SessionPrModel pr;
  final SessionModel session;
  final SessionPrSummaryModel? summary;
  final VoidCallback? onOpenSession;
  final int index;

  @override
  State<PrCard> createState() => _PrCardState();
}

class _PrCardState extends State<PrCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entrance;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.staggerDelay(widget.index);
    final total = delay + AppMotion.slow;
    _controller = AnimationController(vsync: this, duration: total)..forward();
    final startFraction = delay.inMicroseconds / total.inMicroseconds;
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: Interval(startFraction, 1, curve: AppMotion.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _entrance,
    builder: (context, child) => Opacity(
      opacity: _entrance.value,
      child: Transform.translate(offset: Offset(0, AppMotion.fadeUpOffset * (1 - _entrance.value)), child: child),
    ),
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final skin = context.skin;
    final richSummary = widget.summary;
    final pr = widget.pr;
    final session = widget.session;

    final life = richSummary != null ? prLifecycleFromName(richSummary.state) : prLifecycleOf(pr);
    final fallbackVisual = stateVisualOf(skin, life);

    final rawTitle = richSummary?.title?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : prTitle(pr, sessionTitle(session));

    final atoms = richSummary != null ? prStatusAtoms(richSummary) : [prSummaryLine(pr)];
    final blocker = richSummary != null ? prBlockerLine(richSummary) : null;
    final headerColor = atoms.isNotEmpty ? toneColor(skin, atoms.first.tone) : fallbackVisual.color;

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
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      border: Border.all(color: skin.borderDefault),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_merge, size: 16, color: headerColor),
              const HorizontalSpace(6),
              AppText('#${pr.number}', style: AppTextStyle.mono12Bold),
              const HorizontalSpace(6),
              AppText(_lifecycleLabel(life), style: AppTextStyle.style12SemiBold.copyWith(color: headerColor)),
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
              if (widget.onOpenSession != null)
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  tooltip: 'Open session',
                  onPressed: widget.onOpenSession,
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
