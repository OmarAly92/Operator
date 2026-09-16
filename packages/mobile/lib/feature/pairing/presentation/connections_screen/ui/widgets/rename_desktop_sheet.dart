import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

Future<String?> showRenameDesktopSheet(BuildContext context, {required String initialName}) {
  return showExpressiveSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(child: _RenameDesktopSheetBody(initialName: initialName)),
  );
}

class _RenameDesktopSheetBody extends StatefulWidget {
  const _RenameDesktopSheetBody({required this.initialName});

  final String initialName;

  @override
  State<_RenameDesktopSheetBody> createState() => _RenameDesktopSheetBodyState();
}

class _RenameDesktopSheetBodyState extends State<_RenameDesktopSheetBody> {
  late final nameController = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText('Rename desktop', style: AppTextStyle.style17Bold),
        const VerticalSpace(16),
        AppText(
          'Name',
          style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6),
        ),
        const VerticalSpace(6),
        AppTextField(controller: nameController, hintText: 'Studio iMac'),
        const VerticalSpace(20),
        Row(
          children: [
            Expanded(child: _GhostButton(label: 'Cancel', onTap: () => Navigator.of(context).pop())),
            const HorizontalSpace(10),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: nameController,
                builder: (context, nameValue, _) => PrimaryButton(
                  text: 'Save',
                  fixedSize: const Size.fromHeight(46),
                  onPressed: nameValue.text.trim().isEmpty ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return PressScale(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: skin.borderDefault),
              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            ),
            child: AppText(label, style: AppTextStyle.style15SemiBold.copyWith(color: skin.textSecondary)),
          ),
        ),
      ),
    );
  }
}
