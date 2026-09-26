import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';

class ComposerAddButton extends StatelessWidget {
  const ComposerAddButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final tap = onTap;
    return PressScale(
      scale: AppMotion.pressScaleSend,
      enabled: tap != null,
      child: Semantics(
        button: true,
        enabled: tap != null,
        label: 'Add context',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap == null
              ? null
              : () {
                  Haptics.tap();
                  tap();
                },
          child: Container(
            width: ComposerActionButton.size,
            height: ComposerActionButton.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: skin.textPrimary.withValues(alpha: 0.07), shape: BoxShape.circle),
            child: Icon(Icons.add_rounded, size: 22, color: tap == null ? skin.textFaint : skin.textPrimary),
          ),
        ),
      ),
    );
  }
}
