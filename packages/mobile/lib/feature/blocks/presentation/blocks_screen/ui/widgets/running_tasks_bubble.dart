import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';

class RunningTasksBubble extends StatefulWidget {
  const RunningTasksBubble({super.key, required this.count, required this.onTap});

  static const Key capsuleKey = ValueKey('running-tasks-capsule');
  static const double height = 36;

  final int count;
  final VoidCallback onTap;

  static String labelFor(int count) => count == 1 ? '1 running task' : '$count running tasks';

  @override
  State<RunningTasksBubble> createState() => _RunningTasksBubbleState();
}

class _RunningTasksBubbleState extends State<RunningTasksBubble> {
  int _shown = 1;

  void _tap() {
    Haptics.select();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    if (widget.count > 0) _shown = widget.count;
    final label = RunningTasksBubble.labelFor(_shown);
    return Semantics(
      button: true,
      label: '$label, show background tasks',
      excludeSemantics: true,
      onTap: _tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: PressScale(
          child: Container(
            key: RunningTasksBubble.capsuleKey,
            height: RunningTasksBubble.height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: ShapeDecoration(
              color: skin.bgElevated.withValues(alpha: 0.6),
              shape: StadiumBorder(side: BorderSide(color: skin.borderSubtle, width: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RunningTasksAsterisk(color: skin.coral),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyle.style15Medium.copyWith(
                    color: skin.blue,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RunningTasksAsterisk extends StatefulWidget {
  const RunningTasksAsterisk({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  State<RunningTasksAsterisk> createState() => _RunningTasksAsteriskState();
}

class _RunningTasksAsteriskState extends State<RunningTasksAsterisk> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.runningTasksSpin);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spins = !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;
    if (spins && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!spins && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _AsteriskPainter(widget.color),
    ),
  );
}

class _AsteriskPainter extends CustomPainter {
  const _AsteriskPainter(this.color);

  static const int spokes = 8;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = radius * 0.26
      ..strokeCap = StrokeCap.round;
    for (var spoke = 0; spoke < spokes; spoke++) {
      final angle = spoke * math.pi * 2 / spokes - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + direction * radius * 0.2, center + direction * radius * 0.86, paint);
    }
  }

  @override
  bool shouldRepaint(_AsteriskPainter oldDelegate) => oldDelegate.color != color;
}
