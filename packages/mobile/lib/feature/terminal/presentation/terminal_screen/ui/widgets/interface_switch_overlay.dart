import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';

class InterfaceSwitchOverlay extends StatelessWidget {
  const InterfaceSwitchOverlay({
    super.key,
    this.sourceLabel = 'terminal',
    this.targetLabel = 'Chat',
  });

  final String sourceLabel;
  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<InterfaceSwitchCubit>();

    return ColoredBox(
      color: skin.scrim,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: skin.bgSurface,
            border: Border.all(color: skin.borderDefault),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, size: 22, color: skin.blue),
              const VerticalSpace(10),
              AppText(
                'Switching to $targetLabel',
                style: AppTextStyle.style16Bold,
              ),
              const VerticalSpace(10),
              AppText(
                interfaceTransitionLabel(
                  cubit.phase,
                  sourceLabel: sourceLabel,
                  targetLabel: targetLabel,
                ),
                style: AppTextStyle.style12Regular.copyWith(
                  color: skin.textSecondary,
                ),
                maxLines: 4,
                textAlign: TextAlign.center,
              ),
              if (cubit.cancellable) ...[
                const VerticalSpace(14),
                OutlinedButton(
                  onPressed: cubit.cancelling ? null : cubit.cancel,
                  child: AppText(
                    cubit.cancelling ? 'Cancelling…' : 'Cancel switch',
                    style: AppTextStyle.style12SemiBold,
                  ),
                ),
              ],
              if (cubit.error != null) ...[
                const VerticalSpace(10),
                AppText(
                  cubit.error!,
                  style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
