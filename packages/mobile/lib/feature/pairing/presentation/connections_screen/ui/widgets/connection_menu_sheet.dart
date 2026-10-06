import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

sealed class ConnectionMenuResult {
  const ConnectionMenuResult();
}

final class RenameDesktopResult extends ConnectionMenuResult {
  const RenameDesktopResult(this.name);

  final String name;
}

final class RemoveDesktopResult extends ConnectionMenuResult {
  const RemoveDesktopResult();
}

AppSheetPage _renamePage(String initialName) => AppSheetPage(
      title: 'Rename desktop',
      rows: (context, query) => [_RenameDesktopForm(initialName: initialName)],
    );

Future<ConnectionMenuResult?> showConnectionMenuSheet(BuildContext context, {required String name}) {
  return showAppSheet<ConnectionMenuResult>(
    context: context,
    page: AppSheetPage(
      title: name,
      rows: (context, query) => [
        _MenuRow(
          icon: Icons.edit_outlined,
          label: 'Rename',
          onTap: () {
            Haptics.select();
            AppSheet.of(context).push(_renamePage(name));
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
              Navigator.of(context).pop(const RemoveDesktopResult());
            },
          ),
        ),
      ],
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

class _RenameDesktopForm extends StatefulWidget {
  const _RenameDesktopForm({required this.initialName});

  final String initialName;

  @override
  State<_RenameDesktopForm> createState() => _RenameDesktopFormState();
}

class _RenameDesktopFormState extends State<_RenameDesktopForm> {
  late final nameController = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(RenameDesktopResult(nameController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
