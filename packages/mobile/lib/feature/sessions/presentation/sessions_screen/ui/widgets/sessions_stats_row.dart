import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SessionsStatsRow extends StatelessWidget {
  const SessionsStatsRow({super.key, required this.working, required this.needsYou, required this.mergeable});

  final int working;
  final int needsYou;
  final int mergeable;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget stat(int n, String label, Color color) => Expanded(
      child: AppContainer(
        backgroundColor: skin.bgElevated,
        border: Border.all(color: skin.borderSubtle),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText('$n', style: AppTextStyle.mono24Bold.copyWith(color: n > 0 ? color : skin.textFaint)),
            AppText(label, style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary)),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          stat(working, 'working', skin.orange),
          const HorizontalSpace(10),
          stat(needsYou, 'need you', skin.amber),
          const HorizontalSpace(10),
          stat(mergeable, 'mergeable', skin.green),
        ],
      ),
    );
  }
}
