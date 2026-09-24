import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';

class FloatingWorkingControl extends StatefulWidget {
  const FloatingWorkingControl({
    super.key,
    required this.working,
    required this.showLatest,
    required this.onLatest,
    this.since,
    this.coverage,
    this.now = DateTime.now,
  });

  static const Key pillKey = ValueKey('floating-working-pill');
  static const Key latestKey = ValueKey('floating-jump-latest');
  static const double size = 38;
  static const double gap = 8;
  static const double lift = 10;
  static const double coverageHeight = size + lift;

  final bool working;
  final bool showLatest;
  final VoidCallback onLatest;
  final DateTime? Function()? since;
  final ValueNotifier<double>? coverage;
  final DateTime Function() now;

  @override
  State<FloatingWorkingControl> createState() => _FloatingWorkingControlState();
}

class _FloatingWorkingControlState extends State<FloatingWorkingControl> with TickerProviderStateMixin {
  late final AnimationController _pill = AnimationController(vsync: this, value: widget.working ? 1 : 0)
    ..addListener(_report);
  late final AnimationController _latest = AnimationController(vsync: this, value: widget.showLatest ? 1 : 0);
  Timer? _ticker;
  bool _visible = true;
  DateTime? _since;
  String _label = 'Working';

  @override
  void initState() {
    super.initState();
    _refreshSince();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _refreshSince();
    _visible = visible;
    _syncTicker();
  }

  @override
  void didUpdateWidget(FloatingWorkingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshSince();
    if (widget.coverage != oldWidget.coverage) {
      final old = oldWidget.coverage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old?.value = 0;
        if (mounted) _report();
      });
    }
    if (widget.working != oldWidget.working) {
      _drive(_pill, widget.working, AppMotion.control);
      _syncTicker();
    }
    if (widget.showLatest != oldWidget.showLatest) {
      _drive(_latest, widget.showLatest, _pill.value > 0 ? AppMotion.control : AppMotion.controlFade);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pill.dispose();
    _latest.dispose();
    super.dispose();
  }

  bool get _ticks => widget.working && _visible;

  void _refreshSince() {
    if (widget.working) _since = widget.since?.call();
  }

  void _report() {
    final coverage = widget.coverage;
    if (coverage == null) return;
    final value = _pill.value * FloatingWorkingControl.coverageHeight;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      coverage.value = value;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) coverage.value = _pill.value * FloatingWorkingControl.coverageHeight;
    });
  }

  void _drive(AnimationController controller, bool show, Duration duration) {
    final target = show ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = target;
      return;
    }
    controller.animateTo(target, duration: duration, curve: AppMotion.controlCurve);
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = _ticks
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  String _currentLabel() {
    if (!widget.working) return _label;
    final since = _since;
    _label = since == null ? 'Working' : 'Working ${turnElapsed(widget.now().difference(since))}';
    return _label;
  }

  Widget _reveal(double value, Widget child) => Align(
    widthFactor: value,
    child: Transform.scale(scale: value, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final label = _currentLabel();
    return AnimatedBuilder(
      animation: Listenable.merge([_pill, _latest]),
      builder: (context, _) {
        final pill = _pill.value;
        final latest = _latest.value;
        if (pill <= 0 && latest <= 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pill > 0)
              _reveal(
                pill,
                IgnorePointer(
                  child: _WorkingPill(label: label, opacity: pill),
                ),
              ),
            if (pill > 0 && latest > 0) SizedBox(width: FloatingWorkingControl.gap * pill * latest),
            if (latest > 0)
              _reveal(
                latest,
                IgnorePointer(
                  ignoring: !widget.showLatest,
                  child: GlassButton.icon(
                    key: FloatingWorkingControl.latestKey,
                    icon: Icons.keyboard_arrow_down_rounded,
                    semanticLabel: 'Jump to latest',
                    diameter: FloatingWorkingControl.size,
                    foreground: context.skin.textPrimary.withValues(alpha: latest.clamp(0.0, 1.0)),
                    haptic: Haptics.select,
                    onPressed: widget.onLatest,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WorkingPill extends StatelessWidget {
  const _WorkingPill({required this.label, required this.opacity});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final still = MediaQuery.disableAnimationsOf(context);
    return GlassSurface(
      key: FloatingWorkingControl.pillKey,
      kind: GlassShapeKind.capsule,
      size: FloatingWorkingControl.size,
      child: SizedBox(
        height: FloatingWorkingControl.size,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            widthFactor: 1,
            child: AnimatedSize(
              duration: still ? Duration.zero : AppMotion.control,
              curve: AppMotion.controlCurve,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Shimmer(
                  base: skin.textSecondary,
                  highlight: skin.textPrimary,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTextStyle.style13Medium.copyWith(
                      color: skin.textSecondary,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
