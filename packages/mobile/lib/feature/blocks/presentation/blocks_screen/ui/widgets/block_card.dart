import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_action_sheet.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

class BlockCard extends StatelessWidget {
  const BlockCard({
    super.key,
    required this.block,
    this.actionsBuilder,
    this.actions = const [],
    this.onAction,
    this.collapsed = false,
    this.onToggleCollapse,
    this.highlight,
    this.selected = false,
    this.onToggleSelect,
    this.selectionMode = false,
  });

  final SessionBlock block;
  final Widget? Function(SessionBlock block)? actionsBuilder;
  final List<BlockAction> actions;
  final void Function(BlockAction action)? onAction;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final BlockMatch? highlight;
  final bool selected;
  final ValueChanged<bool>? onToggleSelect;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final display = blockDisplay(block);
    final actionsWidget = actionsBuilder?.call(block);
    final summaryHighlight = highlight?.field == BlockMatchField.summary
        ? highlight
        : null;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (display.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: _highlightedField(
              context: context,
              text: display.summary,
              ranges: summaryHighlight?.ranges ?? const <MatchRange>[],
              base: AppTextStyle.mono12Regular.copyWith(
                color: skin.textSecondary,
              ),
              softWrap: true,
            ),
          ),
        if (block.children != null && block.children!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in block.children!)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: BlockCard(
                      key: ValueKey('child-${child.id}'),
                      block: child,
                      actionsBuilder: actionsBuilder,
                    ),
                  ),
              ],
            ),
          ),
        if (display.errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: AppText(
              display.errorText!,
              style: AppTextStyle.style10Regular.copyWith(color: skin.red),
            ),
          ),
        if (block.redacted)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: AppText(
              'Secrets were redacted from this output',
              style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
            ),
          ),
        if (block.truncatedLines > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: AppText(
              '...(truncated)... ${block.truncatedLines} more lines — open Raw for the rest',
              style: AppTextStyle.style10Regular.copyWith(
                color: skin.textTertiary,
              ),
              maxLines: 2,
            ),
          ),
        if (actionsWidget != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: actionsWidget,
          ),
      ],
    );

    final tappableBody = onAction == null || actions.isEmpty
        ? body
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () {
              Haptics.tap();
              showBlockActionSheet(context, actions).then((chosen) {
                if (chosen != null && chosen.kind != BlockActionKind.copyBlock &&
                    chosen.kind != BlockActionKind.copyCommand &&
                    chosen.kind != BlockActionKind.copyOutput) {
                  onAction!(chosen);
                }
              });
            },
            child: body,
          );

    final nameHighlight = highlight?.field == BlockMatchField.displayName
        ? highlight
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlockCardHeader(
            block: block,
            collapsed: collapsed,
            onToggleCollapse: onToggleCollapse,
            nameHighlight: nameHighlight,
          ),
          if (!collapsed) tappableBody,
        ],
      ),
    );
  }
}

Text _highlightedField({
  required BuildContext context,
  required String text,
  required List<MatchRange> ranges,
  required TextStyle base,
  bool softWrap = false,
}) {
  if (ranges.isEmpty) {
    return Text(text, style: base, softWrap: softWrap);
  }
  final skin = context.skin;
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final range in ranges) {
    final start = range.start.clamp(0, text.length);
    final end = (range.start + range.length).clamp(0, text.length);
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start), style: base));
    }
    if (end > start) {
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: base.copyWith(backgroundColor: skin.tintAmber),
        ),
      );
    }
    cursor = end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return Text.rich(
    TextSpan(children: spans),
    softWrap: softWrap,
    style: base,
  );
}

class BlockActionButton extends StatelessWidget {
  const BlockActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Material(
      color: primary ? skin.blue : skin.bgElevated,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: primary ? null : Border.all(color: skin.borderSubtle),
          ),
          child: AppText(
            label,
            style: AppTextStyle.style12SemiBold.copyWith(
              color: primary ? skin.onAccent : skin.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class BlockCardHeader extends StatelessWidget {
  const BlockCardHeader({
    super.key,
    required this.block,
    this.collapsed = false,
    this.onToggleCollapse,
    this.nameHighlight,
  });

  final SessionBlock block;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final BlockMatch? nameHighlight;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final display = blockDisplay(block);
    final tappable = onToggleCollapse != null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          if (tappable) ...[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: skin.textTertiary,
            ),
            const SizedBox(width: 6),
          ],
          BlockStatusDot(status: block.status),
          const SizedBox(width: 8),
          Expanded(
            child: _highlightedField(
              context: context,
              text: display.displayName,
              ranges: nameHighlight?.ranges ?? const <MatchRange>[],
              base: AppTextStyle.style12SemiBold.copyWith(
                color: skin.textPrimary,
              ),
            ),
          ),
          AppText(
            _kindLabel(block.kind),
            style: AppTextStyle.style10Regular.copyWith(
              color: skin.textTertiary,
            ),
          ),
        ],
      ),
    );

    if (!tappable) return content;
    return InkWell(
      onTap: onToggleCollapse,
      child: content,
    );
  }

  String _kindLabel(BlockKind kind) => switch (kind) {
    BlockKind.prompt => 'you',
    BlockKind.assistant => 'agent',
    BlockKind.reasoning => 'reasoning',
    BlockKind.tool => 'tool',
    BlockKind.todo => 'todo',
    BlockKind.compaction => 'compaction',
    BlockKind.permission => 'permission',
    BlockKind.notice => 'notice',
  };
}
