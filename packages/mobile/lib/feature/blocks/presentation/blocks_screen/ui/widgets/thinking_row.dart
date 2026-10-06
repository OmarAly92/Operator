import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';

class ThinkingRow extends StatelessWidget {
  const ThinkingRow({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      label: 'Thinking',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Shimmer(
              base: skin.textTertiary,
              highlight: skin.textPrimary,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_outlined, size: 15, color: skin.textTertiary),
                  const SizedBox(width: 6),
                  Text('Thinking', style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
