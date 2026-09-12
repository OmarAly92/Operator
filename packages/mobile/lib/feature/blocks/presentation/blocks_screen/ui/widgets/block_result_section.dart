import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

const int kResultPreviewLines = 12;

class BlockResultSection extends StatefulWidget {
  const BlockResultSection({super.key, required this.result});

  final String result;

  @override
  State<BlockResultSection> createState() => _BlockResultSectionState();
}

class _BlockResultSectionState extends State<BlockResultSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final lines = widget.result.split('\n');
    final preview = lines.take(kResultPreviewLines).join('\n');
    final long = lines.length > kResultPreviewLines || preview.length > 1200;
    final shortened = preview.length > 1200 ? '${preview.substring(0, 1200)}…' : preview;
    final shown = !long || _expanded ? widget.result : shortened;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: skin.borderSubtle),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Text(
            shown,
            style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
          ),
        ),
        if (long)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: AppText(
                _expanded ? 'Show less' : 'Show full result',
                style: AppTextStyle.style10SemiBold.copyWith(color: skin.accent),
              ),
            ),
          ),
      ],
    );
  }
}
