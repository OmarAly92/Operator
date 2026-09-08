import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

enum ConnectionMenuAction { connect, edit, remove }

Future<ConnectionMenuAction?> showConnectionMenuSheet(BuildContext context, {required String name}) {
  return showExpressiveSheet<ConnectionMenuAction>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(name, style: AppTextStyle.style17Bold, maxLines: 2),
          const VerticalSpace(8),
          _MenuRow(
            icon: Icons.link,
            label: 'Connect',
            onTap: () {
              Haptics.select();
              Navigator.of(sheetContext).pop(ConnectionMenuAction.connect);
            },
          ),
          _MenuDivider(),
          _MenuRow(
            icon: Icons.edit_outlined,
            label: 'Edit details',
            onTap: () {
              Haptics.select();
              Navigator.of(sheetContext).pop(ConnectionMenuAction.edit);
            },
          ),
          _MenuDivider(),
          Builder(
            builder: (context) => _MenuRow(
              icon: Icons.delete_outline,
              label: 'Remove desktop',
              color: context.skin.red,
              onTap: () {
                Haptics.select();
                Navigator.of(sheetContext).pop(ConnectionMenuAction.remove);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(color: context.skin.borderSubtle, height: 1);
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: onTap,
      hapticsOnTap: false,
      borderRadius: BorderRadius.zero,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      height: 52,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color ?? skin.textSecondary),
          const HorizontalSpace(12),
          AppText(label, style: AppTextStyle.style15Medium.copyWith(color: color ?? skin.textPrimary)),
        ],
      ),
    );
  }
}
