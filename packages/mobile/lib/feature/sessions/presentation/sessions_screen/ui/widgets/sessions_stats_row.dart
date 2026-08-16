import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SessionsStatsRow extends StatelessWidget {
  const SessionsStatsRow({
    super.key,
    required this.working,
    required this.needsYou,
    required this.mergeable,
    this.onTapWorking,
    this.onTapNeedsYou,
    this.onTapMergeable,
  });

  final int working;
  final int needsYou;
  final int mergeable;
  final VoidCallback? onTapWorking;
  final VoidCallback? onTapNeedsYou;
  final VoidCallback? onTapMergeable;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget stat(int n, String label, Color color, VoidCallback? onTap) => Expanded(
      child: AppContainer(
        onTap: onTap == null
            ? null
            : () {
                Haptics.select();
                onTap();
              },
        hapticsOnTap: false,
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
          stat(working, 'working', skin.orange, onTapWorking),
          const HorizontalSpace(10),
          stat(needsYou, 'need you', skin.amber, onTapNeedsYou),
          const HorizontalSpace(10),
          stat(mergeable, 'mergeable', skin.green, onTapMergeable),
        ],
      ),
    );
  }
}
