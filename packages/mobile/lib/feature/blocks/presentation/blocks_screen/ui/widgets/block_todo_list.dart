import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

enum PlanStepStatus { pending, active, done }

class PlanStep {
  const PlanStep(this.text, this.status);

  final String text;
  final PlanStepStatus status;
}

/// Parses a todo/plan block's JSON `body` (`{"todos": [{"content", "status"}]}`)
/// into the rail's plan-step vocabulary. Returns an empty list when the body
/// isn't the expected shape, so callers can fall back to a raw-text rendering.
List<PlanStep> parsePlanSteps(String body) {
  if (body.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final raw = decoded['todos'];
  if (raw is! List) return const [];
  final steps = <PlanStep>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final text = entry['content'] as String?;
    if (text == null || text.isEmpty) continue;
    steps.add(PlanStep(text, _statusOf(entry['status'] as String?)));
  }
  return steps;
}

PlanStepStatus _statusOf(String? raw) => switch (raw) {
  'completed' => PlanStepStatus.done,
  'in_progress' => PlanStepStatus.active,
  _ => PlanStepStatus.pending,
};

/// The plan/todo rail body (`isPlan` in `docs/design/session_detail/session_detail.md`):
/// a vertical step list, each row a status icon + label — no card, no border.
class BlockTodoList extends StatelessWidget {
  const BlockTodoList({super.key, required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final steps = parsePlanSteps(body);
    if (steps.isEmpty) {
      return AppText(
        body,
        style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
        maxLines: 200,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (step.status) {
                    PlanStepStatus.done => Icons.check_circle,
                    PlanStepStatus.active => Icons.radio_button_checked,
                    PlanStepStatus.pending => Icons.radio_button_unchecked,
                  },
                  size: 15,
                  color: switch (step.status) {
                    PlanStepStatus.done => skin.green,
                    PlanStepStatus.active => skin.orange,
                    PlanStepStatus.pending => skin.textFaint,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Opacity(
                    opacity: step.status == PlanStepStatus.done ? 0.65 : 1,
                    child: AppText(
                      step.text,
                      style: AppTextStyle.style13Regular.copyWith(
                        color: step.status == PlanStepStatus.pending
                            ? skin.textTertiary
                            : skin.textPrimary,
                        decoration: step.status == PlanStepStatus.done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                      maxLines: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
