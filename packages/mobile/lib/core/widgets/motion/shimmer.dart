import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    required this.base,
    required this.highlight,
    this.enabled = true,
  });

  final Widget child;
  final Color base;
  final Color highlight;
  final bool enabled;

  @visibleForTesting
  static LinearGradient gradientAt({required double t, required Color base, required Color highlight}) {
    return LinearGradient(
      colors: [base, highlight, base],
      stops: const [0.35, 0.5, 0.65],
      transform: _SlidingGradientTransform(_slidePercent(t)),
    );
  }

  static double _slidePercent(double t) {
    final sweepMs = AppMotion.shimmerSweep.inMilliseconds;
    final cycleMs = sweepMs + AppMotion.shimmerPause.inMilliseconds;
    final elapsedMs = t.clamp(0, 1) * cycleMs;
    if (elapsedMs >= sweepMs) return 1;
    return -1 + 2 * (elapsedMs / sweepMs);
  }

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.shimmerSweep + AppMotion.shimmerPause,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController(context);
  }

  @override
  void didUpdateWidget(covariant Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _animates(BuildContext context) =>
      widget.enabled && !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;

  void _syncController(BuildContext context) {
    if (_animates(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animates(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) =>
            Shimmer.gradientAt(t: _controller.value, base: widget.base, highlight: widget.highlight)
                .createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}
