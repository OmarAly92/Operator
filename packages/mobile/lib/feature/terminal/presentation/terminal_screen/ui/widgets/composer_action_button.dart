import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';

enum ComposerAction { mic, send, stop }

ComposerAction composerActionFor({required bool hasText, required bool working, required bool canStop}) {
  if (hasText) return ComposerAction.send;
  if (working && canStop) return ComposerAction.stop;
  return ComposerAction.mic;
}

class ComposerActionButton extends StatelessWidget {
  const ComposerActionButton({super.key, required this.action, this.onSend, this.onStop});

  static const double size = 36;

  final ComposerAction action;
  final VoidCallback? onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : AppMotion.chatActionSwap,
        switchInCurve: AppMotion.easeOut,
        switchOutCurve: AppMotion.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween<double>(begin: 0.8, end: 1).animate(animation), child: child),
        ),
        child: switch (action) {
          ComposerAction.mic => const MicKey(key: ValueKey(ComposerAction.mic), prominent: true, size: size),
          ComposerAction.send => _RoundAction(
            key: const ValueKey(ComposerAction.send),
            label: 'Send',
            icon: Icons.arrow_upward_rounded,
            color: context.skin.accent,
            ink: context.skin.onAccent,
            onTap: onSend,
          ),
          ComposerAction.stop => _RoundAction(
            key: const ValueKey(ComposerAction.stop),
            label: 'Stop',
            icon: Icons.stop_rounded,
            color: context.skin.red,
            ink: context.skin.onAccent,
            onTap: onStop,
          ),
        },
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    scale: AppMotion.pressScaleSend,
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: ComposerActionButton.size,
          height: ComposerActionButton.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: onTap == null ? color.withValues(alpha: 0.5) : color, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: ink),
        ),
      ),
    ),
  );
}
