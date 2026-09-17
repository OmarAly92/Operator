import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlockQuestionOptions extends StatefulWidget {
  const BlockQuestionOptions({
    super.key,
    required this.questions,
    this.interactionId,
    this.answered = false,
    this.answers = const {},
  });

  final List<BlockQuestion> questions;
  final String? interactionId;
  final bool answered;
  final Map<int, List<String>> answers;

  @override
  State<BlockQuestionOptions> createState() => _BlockQuestionOptionsState();
}

class _BlockQuestionOptionsState extends State<BlockQuestionOptions> {
  /// Keyed by question, holding the option LABELS chosen for it. The daemon
  /// resolves labels against the rows actually on screen, so a label carries
  /// its own identity and never depends on a position the harness may have
  /// shifted with a synthetic row.
  final Map<int, List<String>> _selected = {};
  bool _sent = false;

  bool get _multiSelect => widget.questions.any((question) => question.multiSelect == true);

  bool get _actionable => widget.interactionId != null && !widget.answered && !_sent;

  void _select(int question, String label) {
    final interactionId = widget.interactionId;
    if (interactionId == null || label.isEmpty || !_actionable) return;
    Haptics.select();
    if (_multiSelect) {
      setState(() {
        final chosen = _selected.putIfAbsent(question, () => <String>[]);
        if (!chosen.remove(label)) chosen.add(label);
        if (chosen.isEmpty) _selected.remove(question);
      });
      return;
    }
    setState(() {
      _selected[question] = [label];
      _sent = true;
    });
    context.read<SessionCommandCubit>().answer(interactionId, [
      [label],
    ]);
  }

  void _submit() {
    final interactionId = widget.interactionId;
    if (interactionId == null || _selected.isEmpty || !_actionable) return;
    final groups = <List<String>>[];
    for (var question = 0; question < widget.questions.length; question++) {
      final chosen = _selected[question];
      if (chosen != null && chosen.isNotEmpty) groups.add(List<String>.of(chosen));
    }
    if (groups.isEmpty) return;
    Haptics.select();
    setState(() => _sent = true);
    context.read<SessionCommandCubit>().answer(interactionId, groups);
  }

  List<String> _chosen(int question) =>
      widget.answered ? (widget.answers[question] ?? const []) : (_selected[question] ?? const []);

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final settled = widget.answered || _sent;
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
              _optionTile(context, option, question, settled),
          ],
          if (widget.interactionId == null && !widget.answered)
            AppText(
              'Answer in the terminal',
              style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
            )
          else if (_multiSelect && !settled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BlockActionButton(label: 'Submit', primary: true, onTap: _submit),
            )
          else if (_sent && !widget.answered)
            AppText('Sending…', style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary)),
        ],
      ),
    );
  }

  Widget _optionTile(BuildContext context, BlockQuestionOption option, int question, bool settled) {
    final skin = context.skin;
    final label = option.label ?? '';
    final chosen = _chosen(question).contains(label);
    final muted = settled && !chosen;
    final tile = AnimatedContainer(
      duration: AppMotion.fast,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: chosen ? skin.accentTint : skin.bgElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: chosen ? skin.accent : skin.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  style: AppTextStyle.style12SemiBold.copyWith(color: muted ? skin.textTertiary : skin.textPrimary),
                ),
                if ((option.description ?? '').isNotEmpty && option.description != label)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AppText(
                      option.description!,
                      style: AppTextStyle.style10Regular.copyWith(color: muted ? skin.textFaint : skin.textSecondary),
                      maxLines: 4,
                    ),
                  ),
              ],
            ),
          ),
          if (chosen)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_rounded, size: 16, color: skin.accent),
            ),
        ],
      ),
    );
    if (!_actionable) return tile;
    return GestureDetector(onTap: () => _select(question, label), child: tile);
  }
}
