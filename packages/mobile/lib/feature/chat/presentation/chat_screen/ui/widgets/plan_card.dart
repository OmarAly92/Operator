import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

class PlanCard extends StatefulWidget {
  const PlanCard({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  late bool _open = widget.activity.status == 'running';

  @override
  Widget build(BuildContext context) {
    final detail = widget.activity.detail;
    final summary = widget.activity.summary ?? '';
    return PlanShell(
      title: summary.isEmpty ? 'Plan updated' : summary,
      steps: detail?.steps ?? const [],
      explanation: detail?.explanation,
      emptyFallback: detail?.text ?? summary,
      open: _open,
      onToggle: () => setState(() => _open = !_open),
    );
  }
}

class PlanShell extends StatelessWidget {
  const PlanShell({
    super.key,
    required this.title,
    required this.steps,
    required this.open,
    required this.onToggle,
    this.explanation,
    this.emptyFallback,
    this.liveLabel,
  });

  final String title;
  final List<PlanStepModel> steps;
  final bool open;
  final VoidCallback onToggle;
  final String? explanation;
  final String? emptyFallback;
  final String? liveLabel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final done = steps.where((step) => step.status == 'completed').length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.checklist, size: 13, color: skin.textTertiary),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(title, style: AppTextStyle.style12SemiBold),
                  ),
                  if (liveLabel != null) ...[
                    AppText(
                      liveLabel!,
                      style: AppTextStyle.style9Bold.copyWith(
                        color: skin.orange,
                      ),
                    ),
                    const HorizontalSpace(8),
                  ],
                  AppText(
                    '$done/${steps.length}',
                    style: AppTextStyle.mono11Regular.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: skin.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            _PlanBody(
              steps: steps,
              explanation: explanation,
              emptyFallback: emptyFallback,
            ),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.steps, this.explanation, this.emptyFallback});

  final List<PlanStepModel> steps;
  final String? explanation;
  final String? emptyFallback;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (explanation != null)
          AppText(
            explanation!,
            style: AppTextStyle.style12Regular.copyWith(
              color: context.skin.textSecondary,
            ),
            maxLines: 8,
          ),
        for (final step in steps) _PlanStep(step: step),
        if (steps.isEmpty && emptyFallback != null)
          AppText(
            emptyFallback!,
            style: AppTextStyle.style12Regular.copyWith(
              color: context.skin.textSecondary,
            ),
            maxLines: 6,
          ),
      ],
    ),
  );
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({required this.step});

  final PlanStepModel step;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final completed = step.status == 'completed';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: completed
                ? skin.green
                : step.status == 'in_progress'
                ? skin.orange
                : skin.textFaint,
          ),
          const HorizontalSpace(8),
          Expanded(
            child: AppText(
              step.text ?? '',
              style: AppTextStyle.style13Regular.copyWith(
                color: completed ? skin.textTertiary : skin.textPrimary,
                decoration: completed
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
              maxLines: 4,
            ),
          ),
          const HorizontalSpace(8),
          AppText(
            (step.status ?? '').replaceAll('_', ' ').toUpperCase(),
            style: AppTextStyle.style9Bold.copyWith(color: skin.textFaint),
          ),
        ],
      ),
    );
  }
}
