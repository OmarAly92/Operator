import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

enum BlockPermissionKind { approval, userInput }

class BlockCard extends StatelessWidget {
  const BlockCard({
    super.key,
    required this.block,
    this.permissionKind,
    this.onApprove,
    this.onDecline,
    this.onAnswer,
  });

  final SessionBlock block;
  final BlockPermissionKind? permissionKind;
  final void Function(String requestId, String decisionId)? onApprove;
  final void Function(String requestId, String decisionId)? onDecline;
  final void Function(String requestId)? onAnswer;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final display = blockDisplay(block);
    final showApproval =
        block.kind == BlockKind.permission &&
        permissionKind == BlockPermissionKind.approval &&
        block.status == BlockStatus.blocked;
    final showUserInput =
        block.kind == BlockKind.permission &&
        permissionKind == BlockPermissionKind.userInput &&
        block.status == BlockStatus.blocked;
    final requestId = block.id;

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
          BlockCardHeader(block: block),
          if (display.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Text(
                display.summary,
                softWrap: true,
                style: AppTextStyle.mono12Regular.copyWith(
                  color: skin.textSecondary,
                ),
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
                        onAnswer: onAnswer,
                        onApprove: onApprove,
                        onDecline: onDecline,
                        permissionKind: permissionKind,
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
          if (showApproval && (onApprove != null || onDecline != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  if (onApprove != null)
                    Expanded(
                      child: _ActionButton(
                        key: const ValueKey('block-approve'),
                        label: 'Approve',
                        onTap: () => onApprove!(requestId, 'approve'),
                        primary: true,
                      ),
                    ),
                  if (onApprove != null && onDecline != null) const SizedBox(width: 8),
                  if (onDecline != null)
                    Expanded(
                      child: _ActionButton(
                        key: const ValueKey('block-decline'),
                        label: 'Deny',
                        onTap: () => onDecline!(requestId, 'decline'),
                        primary: false,
                      ),
                    ),
                ],
              ),
            ),
          if (showUserInput && onAnswer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _ActionButton(
                key: const ValueKey('block-answer'),
                label: 'Answer',
                onTap: () => onAnswer!(requestId),
                primary: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
  const BlockCardHeader({super.key, required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final display = blockDisplay(block);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          BlockStatusDot(status: block.status),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(
              display.displayName,
              style: AppTextStyle.style12SemiBold.copyWith(
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
