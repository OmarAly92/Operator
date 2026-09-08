import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

/// The three-dot typing/busy indicator (`typingDotsEl`, `saDotBounce` in
/// `docs/design/motion.md`) — each dot bounces up by
/// [AppMotion.dotBounceOffset], staggered by
/// [AppMotion.dotBounceStagger] per dot.
///
/// Animates perpetually while mounted, by design (signals an ongoing
/// "typing"/busy state). See `docs/design/components.md` for the
/// `WidgetTester.pumpAndSettle` implication this has for future callers.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color, this.dotSize = 6, this.gap = 4});

  final Color color;
  final double dotSize;
  final double gap;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.dotBounce)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staggerFraction =
        AppMotion.dotBounceStagger.inMilliseconds / AppMotion.dotBounce.inMilliseconds;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : widget.gap),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = (_controller.value - staggerFraction * i) % 1.0;
              // saDotBounce: translateY 0 -> dotBounceOffset at 30% -> 0.
              final bounce = t <= 0.3
                  ? AppMotion.easeInOut.transform(t / 0.3)
                  : 1 - AppMotion.easeInOut.transform((t - 0.3) / 0.7);
              return Transform.translate(
                offset: Offset(0, AppMotion.dotBounceOffset * bounce),
                child: child,
              );
            },
            child: Container(
              width: widget.dotSize,
              height: widget.dotSize,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          ),
        );
      }),
    );
  }
}
