import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';

export 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart'
    show summarizeActivities;

sealed class TimelineRow {
  const TimelineRow(this.key);

  final String key;
}

final class SingleRow extends TimelineRow {
  const SingleRow(super.key, this.item);

  final ConversationItemModel item;
}

final class ActivitiesRow extends TimelineRow {
  ActivitiesRow(super.key, this.activities);

  final List<ConversationActivityModel> activities;
}

List<TimelineRow> activityRuns(List<ConversationItemModel> items) {
  final rows = <TimelineRow>[];
  for (final item in items) {
    final runnable =
        item is ConversationActivityModel &&
        item.activityKind != 'approval' &&
        item.activityKind != 'user_input' &&
        item.activityKind != 'error' &&
        item.activityKind != 'file_change' &&
        item.activityKind != 'reasoning' &&
        item.detail?.event == null;
    final previous = rows.isEmpty ? null : rows.last;

    if (runnable &&
        previous is ActivitiesRow &&
        previous.activities.first.turnId == item.turnId) {
      previous.activities.add(item);
    } else if (runnable) {
      rows.add(ActivitiesRow('run-${item.sequence ?? 0}', [item]));
    } else {
      rows.add(SingleRow(item.itemKey, item));
    }
  }
  return rows;
}

class ActivityRunWidget extends StatefulWidget {
  const ActivityRunWidget({super.key, required this.activities});

  final List<ConversationActivityModel> activities;

  @override
  State<ActivityRunWidget> createState() => _ActivityRunWidgetState();
}

class _ActivityRunWidgetState extends State<ActivityRunWidget> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final hierarchy = activityHierarchy(widget.activities);
    if (widget.activities.length == 1 && hierarchy.first.children.isEmpty) {
      return ActivityRowWidget(activity: widget.activities.single);
    }

    final running = widget.activities.any(
      (activity) => activity.status == 'running',
    );
    final failed = widget.activities
        .where((activity) => activity.status == 'failed')
        .length;
    final cancelled = widget.activities
        .where((activity) => activity.status == 'cancelled')
        .length;
    final streaming = widget.activities.any(
      (activity) =>
          activity.status == 'running' && activity.detail?.output != null,
    );
    final open = _override ?? streaming;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _override = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      summarizeActivities(widget.activities),
                      style: AppTextStyle.style12Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ),
                  if (failed > 0)
                    AppText(
                      '$failed failed',
                      style: AppTextStyle.style10Regular.copyWith(
                        color: skin.red,
                      ),
                    ),
                  if (cancelled > 0)
                    AppText(
                      '$cancelled stopped',
                      style: AppTextStyle.style10Regular.copyWith(
                        color: skin.textFaint,
                      ),
                    ),
                  if (running)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: skin.textTertiary,
                      ),
                    ),
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: 15,
                    color: skin.textFaint,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final node in hierarchy) _ActivityTree(node: node),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityTree extends StatelessWidget {
  const _ActivityTree({required this.node});

  final ActivityNode node;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ActivityRowWidget(activity: node.activity),
      if (node.children.isNotEmpty) _NestedAgentRun(nodes: node.children),
    ],
  );
}

class _NestedAgentRun extends StatefulWidget {
  const _NestedAgentRun({required this.nodes});

  final List<ActivityNode> nodes;

  @override
  State<_NestedAgentRun> createState() => _NestedAgentRunState();
}

class _NestedAgentRunState extends State<_NestedAgentRun> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final count = countActivityNodes(widget.nodes);
    final running = activityNodesRunning(widget.nodes);

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: skin.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 12,
                    color: skin.textTertiary,
                  ),
                  const HorizontalSpace(6),
                  Expanded(
                    child: AppText(
                      'SUBAGENT · $count ${count == 1 ? 'STEP' : 'STEPS'}',
                      style: AppTextStyle.style9Bold.copyWith(
                        color: skin.textTertiary,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  if (running)
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: skin.textTertiary,
                      ),
                    ),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 12,
                    color: skin.textFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            for (final child in widget.nodes) _ActivityTree(node: child),
        ],
      ),
    );
  }
}
