import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_launch.dart';
import '../glass_lab_probe.dart';

sealed class PerfScenes {
  static const String file = 'perf.json';
  static const Duration warmup = Duration(seconds: 2);
  static const Duration window = Duration(seconds: 6);

  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'perf.none': (launch) => const PerfScene(id: 'perf.none'),
    'perf.glass': (launch) => const PerfScene(id: 'perf.glass'),
    'perf.material': (launch) => const PerfScene(id: 'perf.material'),
    'perf.edge': (launch) => const PerfScene(id: 'perf.edge'),
  };

  static Map<String, double> stats(List<double> values) {
    final sorted = [...values]..sort();
    double at(double q) => sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * q).round()];
    return {'median': at(0.5), 'p90': at(0.9), 'max': at(1)};
  }
}

class PerfScene extends StatefulWidget {
  const PerfScene({super.key, required this.id});

  final String id;

  @override
  State<PerfScene> createState() => _PerfSceneState();
}

class _PerfSceneState extends State<PerfScene> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat();
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(PerfScenes.warmup, _start);
  }

  void _start() {
    if (!mounted) return;
    _recording = true;
    SchedulerBinding.instance.addTimingsCallback(_collect);
    Future<void>.delayed(PerfScenes.window, _finish);
  }

  void _collect(List<FrameTiming> timings) => _timings.addAll(timings);

  void _finish() {
    if (!_recording) return;
    _recording = false;
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    double ms(Duration d) => d.inMicroseconds / 1000;
    writeLabFile(PerfScenes.file, {
      'scene': widget.id,
      'frames': _timings.length,
      'raster_ms': PerfScenes.stats([for (final t in _timings) ms(t.rasterDuration)]),
      'build_ms': PerfScenes.stats([for (final t in _timings) ms(t.buildDuration)]),
    });
  }

  @override
  void dispose() {
    if (_recording) SchedulerBinding.instance.removeTimingsCallback(_collect);
    _motion.dispose();
    super.dispose();
  }

  Widget _glass(double radius, Widget child) => widget.id == 'perf.material'
      ? GlassEffect(child: child)
      : LiquidGlass.withOwnLayer(
          settings: const LiquidGlassSettings(),
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _motion,
          builder: (context, child) => Transform.translate(offset: Offset(-size.width * _motion.value, 0), child: child),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: size.width * 2,
            child: Row(
              children: [
                for (var i = 0; i < 2; i++) SizedBox(width: size.width, height: size.height, child: const GlassLabBackdrop(id: 'stripes')),
              ],
            ),
          ),
        ),
        if (widget.id == 'perf.edge')
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ScrollEdgeEffect(edge: ScrollEdge.top, style: ScrollEdgeStyle.soft, height: MediaQuery.paddingOf(context).top + 94, capExtent: MediaQuery.paddingOf(context).top),
          ),
        if (widget.id == 'perf.glass' || widget.id == 'perf.material')
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var column = 0; column < 3; column++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _glass(22, const SizedBox(width: 110, height: 44)),
                            ),
                        ],
                      ),
                    ),
                  _glass(40, const SizedBox(width: 360, height: 200)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
