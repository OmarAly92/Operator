import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

Future<String?> showSuggestionSheet(
  BuildContext context, {
  required SuggestionKind kind,
  required List<ChatSkillModel> skills,
  required List<String> filePaths,
  required bool filePathsTruncated,
  String initialQuery = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _SuggestionSheet(
      kind: kind,
      skills: skills,
      filePaths: filePaths,
      filePathsTruncated: filePathsTruncated,
      initialQuery: initialQuery,
    ),
  );
}

class _SuggestionSheet extends StatefulWidget {
  const _SuggestionSheet({
    required this.kind,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.initialQuery,
  });

  final SuggestionKind kind;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final String initialQuery;

  @override
  State<_SuggestionSheet> createState() => _SuggestionSheetState();
}

class _SuggestionSheetState extends State<_SuggestionSheet> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final choices = widget.kind == SuggestionKind.skills
        ? rankComposerSkills(widget.skills, _query.text)
        : rankComposerFiles(widget.filePaths, _query.text);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      widget.kind == SuggestionKind.skills
                          ? 'Skills'
                          : 'Worktree files',
                      style: AppTextStyle.style17SemiBold,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      size: 19,
                      color: skin.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppTextStyle.style14Regular.copyWith(
                  color: skin.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.kind == SuggestionKind.skills
                      ? 'Find a skill'
                      : 'Find a file',
                  hintStyle: AppTextStyle.style14Regular.copyWith(
                    color: skin.textFaint,
                  ),
                  filled: true,
                  fillColor: skin.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (widget.kind == SuggestionKind.files &&
                widget.filePathsTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: AppText(
                  "Showing the daemon's capped path list. Narrow your search or type a path directly.",
                  style: AppTextStyle.style10Regular.copyWith(
                    color: skin.amber,
                  ),
                  maxLines: 2,
                ),
              ),
            const VerticalSpace(8),
            Expanded(
              child: choices.isEmpty
                  ? Center(
                      child: AppText(
                        'No matches',
                        style: AppTextStyle.style13Regular.copyWith(
                          color: skin.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(choice.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: skin.borderSubtle),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        choice.label,
                                        style: AppTextStyle.style13SemiBold,
                                      ),
                                      if (choice.detail != null)
                                        AppText(
                                          choice.detail!,
                                          style: AppTextStyle.style11Regular
                                              .copyWith(
                                                color: skin.textTertiary,
                                              ),
                                          maxLines: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                if (choice.badge != null)
                                  AppText(
                                    choice.badge!.toUpperCase(),
                                    style: AppTextStyle.style9Regular.copyWith(
                                      color: skin.textFaint,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
