import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';

class TurnFoldRow extends StatelessWidget {
  const TurnFoldRow({super.key, required this.label, required this.expanded, required this.onTap});

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      expanded: expanded,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.select();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: skin.borderDefault))),
          child: Row(
            children: [
              Flexible(
                child: AppText(
                  label,
                  style: AppTextStyle.style13Medium.copyWith(
                    color: skin.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              DisclosureChevron(
                expanded: expanded,
                size: 16,
                color: skin.textFaint,
                collapsedTurns: -0.25,
                expandedTurns: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
