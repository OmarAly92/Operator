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
  final Set<int> _selected = {};

  bool get _multiSelect => widget.questions.any((question) => question.multiSelect == true);

  void _select(int index) {
    final interactionId = widget.interactionId;
    if (interactionId == null) return;
    if (_multiSelect) {
      setState(() {
        if (!_selected.remove(index)) _selected.add(index);
      });
      return;
    }
    context.read<SessionCommandCubit>().answer(interactionId, [
      [index],
    ]);
  }

  void _submit() {
    final interactionId = widget.interactionId;
    if (interactionId == null || _selected.isEmpty) return;
    context.read<SessionCommandCubit>().answer(interactionId, [_selected.toList()..sort()]);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final actionable = widget.interactionId != null;
    var index = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final question in widget.questions) ...[
            if ((question.header ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AppText(
                  question.header!,
                  style: AppTextStyle.style10SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            for (final option in question.options) _optionTile(context, option, index++, actionable),
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

  Widget _optionTile(BuildContext context, BlockQuestionOption option, int index, bool actionable) {
    final skin = context.skin;
    final selected = actionable && _multiSelect && _selected.contains(index);
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
            option.label ?? '',
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
    return GestureDetector(onTap: () => _select(index), child: tile);
  }
}
