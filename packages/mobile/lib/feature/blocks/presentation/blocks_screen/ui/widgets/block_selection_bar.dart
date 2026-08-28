import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class BlockSelectionBar extends StatelessWidget {
  const BlockSelectionBar({
    super.key,
    required this.selectedIds,
    required this.documentOrder,
    required this.onCancel,
  });

  final Set<String> selectedIds;
  final List<SessionBlock> documentOrder;
  final VoidCallback onCancel;

  void _onCopy(BuildContext context) {
    final docs = [
      for (final block in documentOrder)
        if (selectedIds.contains(block.id)) block,
    ];
    final text = BlockActions.blocksToText(docs);
    Clipboard.setData(ClipboardData(text: text));
    Haptics.success();
    context.showSnackBar('Copied');
    onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppText(
              '${selectedIds.length} selected',
              style: AppTextStyle.style12SemiBold.copyWith(
                color: skin.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: AppText(
              'Cancel',
              style: AppTextStyle.style12SemiBold.copyWith(
                color: skin.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('block-selection-copy'),
            onPressed: selectedIds.isEmpty ? null : () => _onCopy(context),
            child: AppText(
              'Copy',
              style: AppTextStyle.style12SemiBold.copyWith(
                color: selectedIds.isEmpty ? skin.textFaint : skin.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
