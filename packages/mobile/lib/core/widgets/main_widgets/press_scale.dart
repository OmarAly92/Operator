import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

/// Scales [child] down on press-down and back up on release, matching the
/// prototype's `style-active="transform:scale(x)"` press feedback
/// (`docs/design/motion.md` micro-interactions table). Purely visual — does
/// not intercept taps, so wrap it around content that already handles its
/// own `onTap`/`onPressed` (e.g. inside an [InkWell] or [ElevatedButton]).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = AppMotion.pressScaleDefault,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
