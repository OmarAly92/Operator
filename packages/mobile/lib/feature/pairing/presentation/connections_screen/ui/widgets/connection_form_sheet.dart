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

class ConnectionFormResult {
  const ConnectionFormResult({required this.name, required this.address});

  final String name;
  final String address;
}

/// Add/edit sheet for a saved desktop (`docs/design/connections/connections.md`).
///
/// This does NOT reuse `ManualConnectCubit` directly: that cubit models the
/// real host/port/TLS/password `ServerConfig` and performs a live
/// `verifyAndConnect` network call, while this sheet only collects the
/// dummy list entry's Name/Address per the design doc, with no backend call
/// for this UI-only pass. What's reused instead is `manual_connect_body.dart`'s
/// pattern: `TextEditingController`s pre-filled at construction time and a
/// primary button disabled until the fields are non-empty.
Future<ConnectionFormResult?> showConnectionFormSheet(
  BuildContext context, {
  String? initialName,
  String? initialAddress,
}) {
  final isEdit = initialName != null;
  return showExpressiveSheet<ConnectionFormResult>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      child: _ConnectionFormSheetBody(
        isEdit: isEdit,
        initialName: initialName ?? '',
        initialAddress: initialAddress ?? '',
      ),
    ),
  );
}

class _ConnectionFormSheetBody extends StatefulWidget {
  const _ConnectionFormSheetBody({
    required this.isEdit,
    required this.initialName,
    required this.initialAddress,
  });

  final bool isEdit;
  final String initialName;
  final String initialAddress;

  @override
  State<_ConnectionFormSheetBody> createState() => _ConnectionFormSheetBodyState();
}

class _ConnectionFormSheetBodyState extends State<_ConnectionFormSheetBody> {
  late final nameController = TextEditingController(text: widget.initialName);
  late final addressController = TextEditingController(text: widget.initialAddress);

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      ConnectionFormResult(name: nameController.text.trim(), address: addressController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(widget.isEdit ? 'Edit desktop' : 'Add a desktop', style: AppTextStyle.style17Bold),
        const VerticalSpace(16),
        AppText(
          'Name',
          style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6),
        ),
        const VerticalSpace(6),
        AppTextField(controller: nameController, hintText: 'Studio iMac'),
        const VerticalSpace(14),
        AppText(
          'Address',
          style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6),
        ),
        const VerticalSpace(6),
        AppTextField(controller: addressController, hintText: '192.168.1.42', keyboardType: TextInputType.url),
        const VerticalSpace(20),
        Row(
          children: [
            Expanded(child: _GhostButton(label: 'Cancel', onTap: () => Navigator.of(context).pop())),
            const HorizontalSpace(10),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: nameController,
                builder: (context, nameValue, _) => ValueListenableBuilder<TextEditingValue>(
                  valueListenable: addressController,
                  builder: (context, addressValue, _) => PrimaryButton(
                    text: widget.isEdit ? 'Save changes' : 'Add desktop',
                    fixedSize: const Size.fromHeight(46),
                    onPressed: nameValue.text.trim().isEmpty || addressValue.text.trim().isEmpty ? null : _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cancel button — bordered `borderDefault` outline, matching `AppDialog`'s
/// ghost/action button-row spec (`docs/design/components.md`); `PrimaryButton`
/// has no bordered/transparent variant, so this mirrors `AppDialog`'s private
/// `_DialogButton` shape rather than bolting a border option onto it.
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
