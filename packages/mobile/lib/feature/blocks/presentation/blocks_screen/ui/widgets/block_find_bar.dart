import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';

class BlockFindBar extends StatelessWidget {
  const BlockFindBar({
    super.key,
    required this.queryController,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.onToggleFilter,
    required this.currentIndex,
    required this.totalMatches,
    required this.filtering,
    required this.hiddenCount,
  });

  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final ValueChanged<bool> onToggleFilter;
  final int currentIndex;
  final int totalMatches;
  final bool filtering;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final counterText = totalMatches == 0
        ? '0/0'
        : '$currentIndex/$totalMatches';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppTextField(
              controller: queryController,
              hintText: 'Find in blocks',
              onChanged: onQueryChanged,
            ),
          ),
          const SizedBox(width: 8),
          AppText(
            counterText,
            style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
          ),
          IconButton(
            onPressed: onPrevious,
            icon: Icon(Icons.arrow_upward, color: skin.textSecondary),
            tooltip: 'Previous match',
          ),
          IconButton(
            onPressed: onNext,
            icon: Icon(Icons.arrow_downward, color: skin.textSecondary),
            tooltip: 'Next match',
          ),
          IconButton(
            onPressed: () => onToggleFilter(!filtering),
            icon: Icon(
              filtering ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: filtering ? skin.blue : skin.textSecondary,
            ),
            tooltip: 'Filter to matches',
          ),
          if (filtering && hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AppText(
                '$hiddenCount hidden',
                style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
              ),
            ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: skin.textSecondary),
            tooltip: 'Close find',
          ),
        ],
      ),
    );
  }
}
