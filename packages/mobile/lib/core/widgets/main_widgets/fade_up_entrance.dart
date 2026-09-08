import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

/// The prototype's `saFadeUp` staggered-list entrance (`docs/design/motion.md`):
/// opacity 0→1, translateY [AppMotion.fadeUpOffset]→0, delayed by
/// [AppMotion.staggerDelay] for [index], animated over [AppMotion.slow] with
/// [AppMotion.easeOut]. Runs once and rests — safe for `pumpAndSettle`.
///
/// The stagger delay is baked into an [Interval] on the controller's own
/// duration (delay + [AppMotion.slow]) rather than kicked off via
/// `Future.delayed(...).then(controller.forward)`: a bare [Future.delayed]
/// schedules a [Timer] that `pumpAndSettle`'s frame-scheduling check doesn't
/// track, so a widget disposed mid-delay leaves that timer pending and
/// crashes tests with "A Timer is still pending even after the widget tree
/// was disposed." Starting the controller immediately means its single
/// ticker covers the whole span, so `pumpAndSettle` waits on it correctly.
class FadeUpEntrance extends StatefulWidget {
  const FadeUpEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<FadeUpEntrance> createState() => _FadeUpEntranceState();
}

class _FadeUpEntranceState extends State<FadeUpEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.staggerDelay(widget.index);
    final totalDuration = delay + AppMotion.slow;
    _controller = AnimationController(vsync: this, duration: totalDuration);
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / totalDuration.inMicroseconds,
        1,
        curve: AppMotion.easeOut,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, AppMotion.fadeUpOffset * (1 - _curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
