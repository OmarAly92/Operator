import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlockQuestionOptions extends StatefulWidget {
  const BlockQuestionOptions({super.key, required this.questions, this.interactionId});

  final List<BlockQuestion> questions;
  final String? interactionId;

  @override
  State<BlockQuestionOptions> createState() => _BlockQuestionOptionsState();
}

class _BlockQuestionOptionsState extends State<BlockQuestionOptions> {
  /// Keyed by question, holding the option LABELS chosen for it. The daemon
  /// resolves labels against the rows actually on screen, so a label carries
  /// its own identity and never depends on a position the harness may have
  /// shifted with a synthetic row.
  final Map<int, List<String>> _selected = {};

  bool get _multiSelect => widget.questions.any((question) => question.multiSelect == true);

  void _select(int question, String label) {
    final interactionId = widget.interactionId;
    if (interactionId == null || label.isEmpty) return;
    if (_multiSelect) {
      setState(() {
        final chosen = _selected.putIfAbsent(question, () => <String>[]);
        if (!chosen.remove(label)) chosen.add(label);
        if (chosen.isEmpty) _selected.remove(question);
      });
      return;
    }
    context.read<SessionCommandCubit>().answer(interactionId, [
      [label],
    ]);
  }

  void _submit() {
    final interactionId = widget.interactionId;
    if (interactionId == null || _selected.isEmpty) return;
    final groups = <List<String>>[];
    for (var question = 0; question < widget.questions.length; question++) {
      final chosen = _selected[question];
      if (chosen != null && chosen.isNotEmpty) groups.add(List<String>.of(chosen));
    }
    if (groups.isEmpty) return;
    context.read<SessionCommandCubit>().answer(interactionId, groups);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final actionable = widget.interactionId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var question = 0; question < widget.questions.length; question++) ...[
            if ((widget.questions[question].header ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AppText(
                  widget.questions[question].header!,
                  style: AppTextStyle.style10SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            for (final option in widget.questions[question].options)
              _optionTile(context, option, question, actionable),
          ],
          if (!actionable)
            AppText(
              'Answer in the terminal',
              style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
            )
          else if (_multiSelect)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BlockActionButton(label: 'Submit', primary: true, onTap: _submit),
            ),
        ],
      ),
    );
  }

  Widget _optionTile(BuildContext context, BlockQuestionOption option, int question, bool actionable) {
    final skin = context.skin;
    final label = option.label ?? '';
    final selected =
        actionable && _multiSelect && (_selected[question]?.contains(label) ?? false);
    final tile = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: skin.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? skin.blue : skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            label,
            style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
          ),
          if ((option.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppText(
                option.description!,
                style: AppTextStyle.style10Regular.copyWith(color: skin.textSecondary),
                maxLines: 4,
              ),
            ),
        ],
      ),
    );
    if (!actionable) return tile;
    return GestureDetector(onTap: () => _select(question, label), child: tile);
  }
}
