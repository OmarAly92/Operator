import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class BlockNavControls extends StatelessWidget {
  const BlockNavControls({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onLatest,
    required this.showLatest,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLatest;
  final bool showLatest;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: skin.bgElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Step(
                icon: Icons.keyboard_arrow_up,
                onTap: onPrevious,
                tooltip: 'Previous block',
              ),
              _Step(
                icon: Icons.keyboard_arrow_down,
                onTap: onNext,
                tooltip: 'Next block',
              ),
            ],
          ),
        ),
        if (showLatest) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onLatest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: skin.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AppText(
                'Jump to latest',
                style: AppTextStyle.style11SemiBold.copyWith(
                  color: skin.onAccent,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 32,
        child: Icon(icon, size: 18, color: context.skin.textSecondary),
      ),
    ),
  );
}
