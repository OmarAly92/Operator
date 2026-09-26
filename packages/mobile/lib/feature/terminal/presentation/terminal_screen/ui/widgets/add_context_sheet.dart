import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

const String kAttachFailed = 'Could not attach that. Try again.';

typedef AttachmentPick = Future<List<ComposerAttachment>> Function(AttachmentPicker picker, int room);

Future<void> showAddContextSheet(BuildContext context) {
  final terminal = context.read<TerminalCubit>();
  return showAppSheet<void>(
    context: context,
    detent: AppSheetDetent.fit,
    scope: (sheetContext, sheet) => BlocProvider<TerminalCubit>.value(value: terminal, child: sheet),
    page: AppSheetPage(
      title: 'Add context',
      closeable: true,
      rows: (context, _) => const [AddContextBody()],
    ),
  );
}

class AddContextBody extends StatelessWidget {
  const AddContextBody({super.key});

  static const Key cameraKey = ValueKey('add-context-camera');
  static const Key photosKey = ValueKey('add-context-photos');
  static const Key filesKey = ValueKey('add-context-files');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Row(
        spacing: 10,
        children: [
          Expanded(
            child: AddContextTile(
              key: cameraKey,
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              onTap: () => unawaited(_pick(context, (picker, _) => picker.camera())),
            ),
          ),
          Expanded(
            child: AddContextTile(
              key: photosKey,
              icon: Icons.photo_library_outlined,
              label: 'Photos',
              onTap: () => unawaited(_pick(context, (picker, room) => picker.photos(limit: room))),
            ),
          ),
          Expanded(
            child: AddContextTile(
              key: filesKey,
              icon: Icons.attach_file_rounded,
              label: 'Files',
              onTap: () => unawaited(_pick(context, (picker, _) => picker.files())),
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pick(BuildContext context, AttachmentPick pick) async {
  final terminal = context.read<TerminalCubit>();
  final sheet = AppSheet.of(context);
  final room = AttachmentLimits.maxCount - terminal.attachments.length;
  if (room <= 0) {
    terminal.showAttachmentNotice(kTooManyFiles);
    sheet.close();
    return;
  }
  try {
    final picked = await pick(sl<AttachmentPicker>(), room);
    if (picked.isEmpty) return;
    terminal.addAttachments(picked);
  } on AttachmentPickFailure catch (failure) {
    terminal.showAttachmentNotice(failure.message);
  } catch (_) {
    terminal.showAttachmentNotice(kAttachFailed);
  }
  sheet.close();
}

class AddContextTile extends StatelessWidget {
  const AddContextTile({super.key, required this.icon, required this.label, required this.onTap});

  static const double height = 76;

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return PressScale(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: skin.bgElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Icon(icon, size: 24, color: skin.textPrimary),
                Text(label, style: AppTextStyle.style13Medium.copyWith(color: skin.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
