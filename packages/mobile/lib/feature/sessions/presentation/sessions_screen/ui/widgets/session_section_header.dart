import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class SessionSectionHeader extends StatelessWidget {
  const SessionSectionHeader({super.key, required this.label, required this.color, required this.count});

  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Row(
      children: [
        AppText(label.toUpperCase(), style: AppTextStyle.style11SemiBold.copyWith(color: color)),
        const SizedBox(width: 6),
        AppText('$count', style: AppTextStyle.mono11Regular.copyWith(color: color)),
      ],
    ),
  );
}
