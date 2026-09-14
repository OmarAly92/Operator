import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';

Future<String?> showClaudeAccountPickerSheet(
  BuildContext context, {
  required List<ClaudeAccountModel> accounts,
  required String selected,
}) {
  final skin = context.skin;
  return showExpressiveSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('Claude account', style: AppTextStyle.style17SemiBold),
          const VerticalSpace(4),
          AppText(
            'Which Claude login this session runs on.',
            style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
            maxLines: 2,
          ),
          const VerticalSpace(8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final account in accounts)
                  AppInkWell(
                    onTap: () {
                      Haptics.select();
                      Navigator.of(sheetContext).pop(account.id);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  account.label ?? account.id ?? '',
                                  style: AppTextStyle.style15Medium.copyWith(
                                    color: account.id == selected ? skin.accent : skin.textPrimary,
                                  ),
                                ),
                                AppText(
                                  account.planLabel,
                                  style: AppTextStyle.style12Regular.copyWith(
                                    color: account.loggedIn == true ? skin.textTertiary : skin.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (account.id == selected) Icon(Icons.check, size: 18, color: skin.accent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
