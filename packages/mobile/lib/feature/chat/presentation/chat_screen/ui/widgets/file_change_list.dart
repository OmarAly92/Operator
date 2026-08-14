import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart';

class FileChangeActivity extends StatefulWidget {
  const FileChangeActivity({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<FileChangeActivity> createState() => _FileChangeActivityState();
}

class _FileChangeActivityState extends State<FileChangeActivity> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final files = DiffFileModel.listFrom(detail?.files);
    final fallbackPatch = detail?.patchOutput;
    final live = widget.activity.status == 'running';
    final open =
        _override ??
        (live &&
            (fallbackPatch != null || files.any((file) => file.patch != null)));
    final expandable = files.isNotEmpty || fallbackPatch != null;
    final summary = widget.activity.summary;
    final title = summary != null && summary.isNotEmpty
        ? summary
        : '${files.length} changed ${files.length == 1 ? 'file' : 'files'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: expandable ? () => setState(() => _override = !open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 13, color: skin.blue),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(
                    title,
                    style: AppTextStyle.style12Regular.copyWith(
                      color: skin.textSecondary,
                    ),
                  ),
                ),
                if (expandable)
                  Icon(
                    open ? Icons.expand_less : Icons.chevron_right,
                    size: 15,
                    color: skin.textFaint,
                  ),
              ],
            ),
          ),
        ),
        if (open)
          FileChangeList(
            files: files,
            live: live,
            fallbackPatch: fallbackPatch,
            fallbackPatchTruncated: detail?.patchOutputTruncated == true,
          ),
      ],
    );
  }
}

class FileChangeList extends StatelessWidget {
  const FileChangeList({
    super.key,
    required this.files,
    this.live = false,
    this.fallbackPatch,
    this.fallbackPatchTruncated = false,
  });

  final List<DiffFileModel> files;
  final bool live;
  final String? fallbackPatch;
  final bool fallbackPatchTruncated;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 21, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in files) FileChangeRow(file: file, live: live),
        if (fallbackPatch != null)
          PatchBlock(patch: fallbackPatch!, truncated: fallbackPatchTruncated),
      ],
    ),
  );
}

class FileChangeRow extends StatefulWidget {
  const FileChangeRow({super.key, required this.file, this.live = false});

  final DiffFileModel file;
  final bool live;

  @override
  State<FileChangeRow> createState() => _FileChangeRowState();
}

class _FileChangeRowState extends State<FileChangeRow> {
  late bool _open = widget.live && widget.file.patch != null;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final file = widget.file;
    final mark = switch (file.status) {
      'added' => 'A',
      'deleted' => 'D',
      'renamed' => 'R',
      _ => 'M',
    };
    final color = switch (file.status) {
      'deleted' => skin.red,
      'added' => skin.green,
      _ => skin.blue,
    };
    final path = file.oldPath == null
        ? file.path ?? ''
        : '${file.oldPath} → ${file.path ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: file.patch == null
              ? null
              : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                AppText(
                  mark,
                  style: AppTextStyle.mono11Bold.copyWith(color: color),
                ),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(
                    path,
                    style: AppTextStyle.mono11Regular.copyWith(
                      color: skin.textSecondary,
                    ),
                    maxLines: 2,
                  ),
                ),
                AppText(
                  '+${file.additions ?? 0} −${file.deletions ?? 0}',
                  style: AppTextStyle.mono10Regular.copyWith(
                    color: skin.textFaint,
                  ),
                ),
                if (file.patch != null)
                  Icon(
                    _open ? Icons.expand_less : Icons.chevron_right,
                    size: 13,
                    color: skin.textFaint,
                  ),
              ],
            ),
          ),
        ),
        if (_open && file.patch != null)
          PatchBlock(
            patch: file.patch!,
            truncated: file.patchTruncated == true,
          ),
      ],
    );
  }
}

class PatchBlock extends StatelessWidget {
  const PatchBlock({super.key, required this.patch, this.truncated = false});

  final String patch;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () => Clipboard.setData(ClipboardData(text: patch)),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: skin.bgColumn,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightedCodeText(
                code: patch,
                language: 'diff',
                style: AppTextStyle.mono11Regular,
              ),
            ),
          ),
        ),
        if (truncated)
          const PartialNote(
            warning: true,
            text:
                'This patch is longer than Operator stores. The complete change remains in the worktree.',
          ),
      ],
    );
  }
}

class FileNameList extends StatelessWidget {
  const FileNameList({super.key, required this.files});

  final List<dynamic> files;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final file in files)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: AppText(
            '• ${file is String ? file : file.toString()}',
            style: AppTextStyle.mono11Regular.copyWith(
              color: context.skin.textSecondary,
            ),
            maxLines: 2,
          ),
        ),
    ],
  );
}
