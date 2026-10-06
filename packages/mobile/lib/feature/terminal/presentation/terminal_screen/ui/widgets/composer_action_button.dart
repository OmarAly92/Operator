import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';

enum ComposerAction { mic, send }

ComposerAction composerActionFor({required bool hasText, required bool recording}) {
  if (recording) return ComposerAction.mic;
  return hasText ? ComposerAction.send : ComposerAction.mic;
}

Widget _swapTransition(Widget child, Animation<double> animation) => _IgnoreWhileLeaving(
  animation: animation,
  child: FadeTransition(
    opacity: animation,
    child: ScaleTransition(scale: Tween<double>(begin: 0.8, end: 1).animate(animation), child: child),
  ),
);

class _IgnoreWhileLeaving extends StatefulWidget {
  const _IgnoreWhileLeaving({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_IgnoreWhileLeaving> createState() => _IgnoreWhileLeavingState();
}

class _IgnoreWhileLeavingState extends State<_IgnoreWhileLeaving> {
  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_IgnoreWhileLeaving oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation == oldWidget.animation) return;
    oldWidget.animation.removeStatusListener(_onStatus);
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final status = widget.animation.status;
    return IgnorePointer(
      ignoring: status == AnimationStatus.reverse || status == AnimationStatus.dismissed,
      child: widget.child,
    );
  }
}

class ComposerActionButton extends StatelessWidget {
  const ComposerActionButton({super.key, required this.action, this.onSend});

  static const double size = 36;

  final ComposerAction action;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : AppMotion.chatActionSwap,
        switchInCurve: AppMotion.easeOut,
        switchOutCurve: AppMotion.easeOut,
        transitionBuilder: _swapTransition,
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

enum ComposerTrailing { none, send, stop }

ComposerTrailing composerTrailingFor({required bool hasContent, required bool canStop}) {
  if (hasContent) return ComposerTrailing.send;
  return canStop ? ComposerTrailing.stop : ComposerTrailing.none;
}

class ComposerSendSlot extends StatelessWidget {
  const ComposerSendSlot({super.key, required this.trailing, required this.staging, this.onSend, this.onStop});

  static const Key stagingKey = ValueKey('composer-staging');
  static const double gap = 6;

  final ComposerTrailing trailing;
  final bool staging;
  final VoidCallback? onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : AppMotion.chatActionSwap,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: _swapTransition,
      child: switch (trailing) {
        ComposerTrailing.send when staging => const Padding(
          key: stagingKey,
          padding: EdgeInsets.only(left: ComposerSendSlot.gap),
          child: _StagingIndicator(),
        ),
        ComposerTrailing.send => Padding(
          key: const ValueKey(ComposerTrailing.send),
          padding: const EdgeInsets.only(left: ComposerSendSlot.gap),
          child: _RoundAction(
            label: 'Send',
            icon: Icons.arrow_upward_rounded,
            color: skin.accent,
            ink: skin.onAccent,
            onTap: onSend,
          ),
        ),
        ComposerTrailing.stop => Padding(
          key: const ValueKey(ComposerTrailing.stop),
          padding: const EdgeInsets.only(left: ComposerSendSlot.gap),
          child: _RoundAction(
            label: 'Stop',
            icon: Icons.stop_rounded,
            color: skin.red,
            ink: skin.onAccent,
            onTap: onStop,
          ),
        ),
        ComposerTrailing.none => const SizedBox.shrink(key: ValueKey(ComposerTrailing.none)),
      },
    );
  }
}

class _StagingIndicator extends StatelessWidget {
  const _StagingIndicator();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      label: 'Uploading attachments',
      child: Container(
        width: ComposerActionButton.size,
        height: ComposerActionButton.size,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: skin.accent.withValues(alpha: 0.5), shape: BoxShape.circle),
        child: CircularProgressIndicator(strokeWidth: 2, color: skin.onAccent),
      ),
    );
  }
}
