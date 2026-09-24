import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/pickers/picker_filter.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';

const String kClaudeAccountPickerTitle = 'Claude account';
const String kClaudeAccountPickerSubtitle = 'Which Claude login this session runs on.';
const String kClaudeAccountPickerSearchHint = 'Search accounts';

AppSheetPage claudeAccountPickerPage({
  required List<ClaudeAccountModel> accounts,
  required String selected,
  required void Function(BuildContext context, String id) onPicked,
}) {
  return AppSheetPage(
    title: kClaudeAccountPickerTitle,
    subtitle: kClaudeAccountPickerSubtitle,
    searchHint: kClaudeAccountPickerSearchHint,
    rows: (context, query) => [
      for (final account in accounts)
        if (PickerFilter.matches(query, [account.label, account.id, account.planLabel]))
          _AccountOption(
            account: account,
            selected: account.id == selected,
            onTap: () {
              Haptics.select();
              final id = account.id;
              if (id == null) {
                Navigator.of(context).pop();
              } else {
                onPicked(context, id);
              }
            },
          ),
    ],
  );
}

class _AccountOption extends StatelessWidget {
  const _AccountOption({required this.account, required this.selected, required this.onTap});

  final ClaudeAccountModel account;
  final bool selected;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppInkWell(
      onTap: onTap,
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
                    style: AppTextStyle.style15Medium.copyWith(color: selected ? skin.accent : skin.textPrimary),
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
            if (selected) Icon(Icons.check, size: 18, color: skin.accent),
          ],
        ),
      ),
    );
  }
}
