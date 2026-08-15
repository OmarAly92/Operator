import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

enum InterfaceSwitchChoice { drain, interrupt }

/// The agent is mid-turn, so the user must choose what happens to it. Three
/// options, which `AppDialog.confirm` cannot express.
Future<InterfaceSwitchChoice?> showInterfaceSwitchSheet(
  BuildContext context, {
  required String targetLabel,
  required bool waitingOnInput,
}) => showModalBottomSheet<InterfaceSwitchChoice>(
  context: context,
  backgroundColor: context.skin.bgSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
  ),
  builder: (sheetContext) {
    final skin = sheetContext.skin;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText('Switch to $targetLabel?', style: AppTextStyle.style16SemiBold),
            const VerticalSpace(8),
            AppText(
              waitingOnInput
                  ? 'This turn is waiting for your input. Finish waits for your answer; stop cancels it and switches now.'
                  : 'Keep the same Operator session, worktree, and native agent conversation.',
              style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
              maxLines: 4,
            ),
            const VerticalSpace(14),
            TextButton(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(InterfaceSwitchChoice.drain),
              child: AppText('Finish, then switch', style: AppTextStyle.style14SemiBold),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(InterfaceSwitchChoice.interrupt),
              child: AppText(
                'Stop and switch',
                style: AppTextStyle.style14SemiBold.copyWith(color: skin.red),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: AppText(
                'Keep Terminal UI',
                style: AppTextStyle.style14Medium.copyWith(color: skin.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
