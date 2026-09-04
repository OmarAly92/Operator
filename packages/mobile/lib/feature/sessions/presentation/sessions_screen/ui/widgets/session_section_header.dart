import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class SessionSectionHeader extends StatelessWidget {
  const SessionSectionHeader({
    super.key,
    required this.label,
    required this.color,
    required this.count,
    this.onTap,
    this.expanded,
  });

  final String label;
  final Color color;
  final int count;
  final void Function()? onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (expanded != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(expanded! ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: color),
          ),
        AppText(label.toUpperCase(), style: AppTextStyle.style11SemiBold.copyWith(color: color)),
        const SizedBox(width: 6),
        AppText('$count', style: AppTextStyle.mono11Regular.copyWith(color: color)),
      ],
    );
    final padded = Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 8), child: row);
    if (onTap == null) return padded;
    return Semantics(
      button: true,
      expanded: expanded,
      child: AppInkWell(onTap: onTap, child: padded),
    );
  }
}
