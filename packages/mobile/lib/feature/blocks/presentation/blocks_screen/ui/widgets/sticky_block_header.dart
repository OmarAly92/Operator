import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_todo_list.dart';

class StickyBlock extends Equatable {
  const StickyBlock({required this.block, required this.height});

  final SessionBlock block;
  final double height;

  @override
  List<Object?> get props => [
    block.id,
    block.status,
    block.title,
    block.kind,
    height,
  ];
}

class StickyBlockHeader extends StatelessWidget {
  const StickyBlockHeader({super.key, required this.sticky, this.trailing});

  final ValueListenable<StickyBlock?> sticky;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StickyBlock?>(
    valueListenable: sticky,
    builder: (context, value, _) {
      if (value == null) return const SizedBox.shrink();
      final block = value.block;
      if (block.kind == BlockKind.tool || !railKindHasHeader(railKindOf(block))) {
        return const SizedBox.shrink();
      }
      final skin = context.skin;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: skin.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusMd)),
          border: Border.all(color: skin.borderSubtle),
        ),
        child: Row(
          children: [
            BlockStatusDot(status: block.status, overrideColor: railNodeColor(skin, block), size: 8),
            const SizedBox(width: 8),
            Expanded(child: _stickyLabel(context, block)),
            if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing!),
          ],
        ),
      );
    },
  );

  Widget _stickyLabel(BuildContext context, SessionBlock block) {
    final skin = context.skin;
    final display = blockDisplay(block);
    if (railKindOf(block) == RailKind.plan) {
      final steps = parsePlanSteps(block.body);
      final done = steps.where((step) => step.status == PlanStepStatus.done).length;
      return AppText(
        steps.isEmpty ? 'Plan' : 'Plan · $done of ${steps.length} done',
        style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return AppText(
      display.displayName,
      style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
