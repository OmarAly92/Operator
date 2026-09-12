import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

class ToolGroupHeader extends StatelessWidget {
  const ToolGroupHeader({
    super.key,
    required this.count,
    required this.status,
    required this.expanded,
    required this.onTap,
    this.onLongPress,
  });

  final int count;
  final BlockStatus status;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final label = switch (status) {
      BlockStatus.running => 'Using $count tools',
      BlockStatus.failed => 'Used $count tools · failed',
      _ => 'Used $count tools',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                if (status != BlockStatus.ok) ...[
                  BlockStatusDot(status: status),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: AppText(
                    label,
                    maxLines: 2,
                    style: AppTextStyle.style13Medium.copyWith(
                      color: status == BlockStatus.failed
                          ? skin.red
                          : skin.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: skin.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
