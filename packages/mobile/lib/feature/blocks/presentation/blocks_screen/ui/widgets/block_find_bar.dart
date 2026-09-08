import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

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
        color: skin.bgChrome,
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        spacing: 2,
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: queryController,
                onChanged: onQueryChanged,
                style: AppTextStyle.style13Regular.copyWith(
                  color: skin.textPrimary,
                  fontSize: 13,
                ),
                cursorColor: skin.accent,
                decoration: InputDecoration(
                  hintText: 'Find in blocks',
                  hintStyle: AppTextStyle.style13Regular.copyWith(
                    color: skin.textPrimary.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: skin.bgElevated,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: skin.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: skin.borderDefault),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: skin.borderDefault),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppText(
              counterText,
              style: AppTextStyle.style11Regular.copyWith(
                color: skin.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            iconSize: 18,
            onPressed: onPrevious,
            icon: Icon(Icons.arrow_upward, color: skin.textSecondary),
            tooltip: 'Previous match',
          ),
          IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            iconSize: 18,
            onPressed: onNext,
            icon: Icon(Icons.arrow_downward, color: skin.textSecondary),
            tooltip: 'Next match',
          ),
          IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            iconSize: 18,
            onPressed: () => onToggleFilter(!filtering),
            icon: Icon(
              filtering ? Icons.filter_alt : Icons.filter_alt_off_outlined,
              color: filtering ? skin.blue : skin.textSecondary,
            ),
            tooltip: 'Filter to matches',
          ),
          if (filtering && hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AppText(
                '$hiddenCount hidden',
                style: AppTextStyle.style10Regular.copyWith(
                  color: skin.textTertiary,
                ),
              ),
            ),
          IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            iconSize: 18,
            onPressed: onClose,
            icon: Icon(Icons.close, color: skin.textSecondary),
            tooltip: 'Close find',
          ),
        ],
      ),
    );
  }
}
