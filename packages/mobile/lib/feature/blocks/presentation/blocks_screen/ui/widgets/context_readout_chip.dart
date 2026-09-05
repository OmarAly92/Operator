import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/usage/logic/context_readout.dart';

class ContextReadoutChip extends StatelessWidget {
  const ContextReadoutChip({super.key, required this.readout});

  final ContextReadoutData? readout;

  @override
  Widget build(BuildContext context) {
    final current = readout;
    if (current == null) return const SizedBox.shrink();

    final skin = context.skin;
    final readoutColor = switch (current.severity) {
      ContextSeverity.critical => skin.red,
      ContextSeverity.warn => skin.amber,
      ContextSeverity.normal => skin.blue,
    };
    final percentLabel = current.percentLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: skin.bgElevated,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(6),
      ),
      child: percentLabel == null
          ? AppText(
              current.label,
              style: AppTextStyle.style11Regular.copyWith(
                color: skin.textTertiary,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: current.fraction,
                      backgroundColor: skin.bgSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(readoutColor),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppText(
                  percentLabel,
                  style: AppTextStyle.style11Regular.copyWith(
                    color: readoutColor,
                  ),
                ),
              ],
            ),
    );
  }
}
