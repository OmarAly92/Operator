import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';

String _labelFor(BlockAction action) => switch (action.kind) {
  BlockActionKind.copyBlock => 'Copy block',
  BlockActionKind.copyCommand => 'Copy command',
  BlockActionKind.copyOutput => 'Copy output',
  BlockActionKind.rerun => 'Re-run this prompt',
  BlockActionKind.rewind => 'Rewind the conversation',
};

bool _isCopy(BlockAction action) => switch (action.kind) {
  BlockActionKind.copyBlock ||
  BlockActionKind.copyCommand ||
  BlockActionKind.copyOutput =>
    true,
  BlockActionKind.rerun || BlockActionKind.rewind => false,
};

Future<BlockAction?> showBlockActionSheet(
  BuildContext context,
  List<BlockAction> actions,
) {
  Haptics.tap();
  return showModalBottomSheet<BlockAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _BlockActionSheet(actions: actions),
  );
}

class _BlockActionSheet extends StatelessWidget {
  const _BlockActionSheet({required this.actions});

  final List<BlockAction> actions;

  void _onTap(BuildContext sheetContext, BlockAction action) {
    Navigator.of(sheetContext).pop();
    if (_isCopy(action)) {
      Clipboard.setData(ClipboardData(text: action.payload ?? ''));
      Haptics.success();
      sheetContext.showSnackBar('Copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          for (final action in actions)
            InkWell(
              onTap: () => _onTap(context, action),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: skin.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        _labelFor(action),
                        style: AppTextStyle.style13SemiBold,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 15, color: skin.textFaint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
