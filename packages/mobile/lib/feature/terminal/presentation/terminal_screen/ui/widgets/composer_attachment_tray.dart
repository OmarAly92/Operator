import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class ComposerAttachmentTray extends StatelessWidget {
  const ComposerAttachmentTray({
    super.key,
    required this.attachments,
    this.notice,
    this.onRemove,
    this.onDismissNotice,
  });

  static const double thumbSize = 56;
  static const double fileCardWidth = 148;
  static const double badgeSize = 22;
  static const double removeHitSize = 44;
  static const Key noticeKey = ValueKey('composer-attachment-notice');

  final List<ComposerAttachment> attachments;
  final String? notice;
  final void Function(String id)? onRemove;
  final VoidCallback? onDismissNotice;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = notice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (attachments.isNotEmpty)
            SizedBox(
              height: thumbSize + badgeSize / 2,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _TrayItem(attachment: attachments[index], onRemove: onRemove),
              ),
            ),
          if (text != null)
            Semantics(
              button: true,
              hint: 'Dismiss',
              child: GestureDetector(
                key: noticeKey,
                behavior: HitTestBehavior.opaque,
                onTap: onDismissNotice,
                child: Text(text, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  const _TrayItem({required this.attachment, required this.onRemove});

  final ComposerAttachment attachment;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final remove = onRemove;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: ComposerAttachmentTray.badgeSize / 2,
            right: ComposerAttachmentTray.badgeSize / 2,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: attachment.isImage
                ? Image.memory(
                    attachment.bytes,
                    width: ComposerAttachmentTray.thumbSize,
                    height: ComposerAttachmentTray.thumbSize,
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    gaplessPlayback: true,
                    semanticLabel: attachment.name,
                    errorBuilder: (_, _, _) =>
                        _FileCard(name: attachment.name, width: ComposerAttachmentTray.thumbSize),
                  )
                : _FileCard(name: attachment.name, width: ComposerAttachmentTray.fileCardWidth),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            container: true,
            button: true,
            enabled: remove != null,
            label: 'Remove ${attachment.name}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: remove == null ? null : () => remove(attachment.id),
              child: SizedBox.square(
                dimension: ComposerAttachmentTray.removeHitSize,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: ComposerAttachmentTray.badgeSize,
                    height: ComposerAttachmentTray.badgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.borderSubtle),
                    ),
                    child: Icon(Icons.close_rounded, size: 14, color: skin.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.name, required this.width});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      width: width,
      height: ComposerAttachmentTray.thumbSize,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: skin.textPrimary.withValues(alpha: 0.07),
      child: Row(
        spacing: 8,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 20, color: skin.textSecondary),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.style12Medium.copyWith(color: skin.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
