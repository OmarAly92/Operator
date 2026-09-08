import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

/// A colored status dot with the prototype's `breatheDot` opacity pulse
/// (`docs/design/motion.md`) — used on session/status cards. Pass
/// [breathing] `true` while the represented state is active/busy
/// ([AppMotion.breatheActive]) or stopped/idle
/// ([AppMotion.breatheIdle] via [idle]); `false` renders a static dot.
///
/// This animates perpetually while [breathing] is true — by design, since it
/// signals an ongoing state. A screen that renders this and stays mounted
/// while breathing will make `WidgetTester.pumpAndSettle` hang; use bounded
/// `pump(duration)` calls in tests instead (see `docs/design/components.md`).
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 7,
    this.breathing = false,
    this.idle = false,
  });

  final Color color;
  final double size;
  final bool breathing;

  /// When [breathing] is true, selects [AppMotion.breatheIdle] instead of
  /// [AppMotion.breatheActive] as the pulse period.
  final bool idle;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration get _period => widget.idle ? AppMotion.breatheIdle : AppMotion.breatheActive;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    if (widget.breathing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.breathing != widget.breathing || oldWidget.idle != widget.idle) {
      _controller.duration = _period;
      if (widget.breathing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.breathing) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.easeInOut),
      ),
      child: dot,
    );
  }
}
