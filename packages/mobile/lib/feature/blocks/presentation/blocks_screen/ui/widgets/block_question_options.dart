import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class BlockQuestionOptions extends StatelessWidget {
  const BlockQuestionOptions({super.key, required this.questions});

  final List<BlockQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final question in questions) ...[
            if ((question.header ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AppText(
                  question.header!,
                  style: AppTextStyle.style10SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            for (final option in question.options)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: skin.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: skin.borderSubtle),
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
              ),
          ],
          AppText(
            'Answer in the terminal',
            style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }
}
