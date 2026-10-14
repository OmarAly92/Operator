import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
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
    'perf.motion': (launch) => const PerfScene(id: 'perf.motion'),
    'perf.slide': (launch) => const PerfScene(id: 'perf.slide'),
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

  Widget _glass(double radius, Widget child) => widget.id == 'perf.material' || widget.id == 'perf.slide'
      ? GlassEffect(child: child)
      : LiquidGlass.withOwnLayer(
          settings: const LiquidGlassSettings(),
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          child: child,
        );

  Widget _layout() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var row = 0; row < 4; row++)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var column = 0; column < 3; column++)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _glass(22, const SizedBox(width: 110, height: 44))),
            ],
          ),
        ),
      _glass(40, const SizedBox(width: 360, height: 200)),
    ],
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
        if (widget.id == 'perf.motion') SafeArea(child: Center(child: PerfMotion(clock: _motion))),
        if (widget.id == 'perf.glass' || widget.id == 'perf.material') SafeArea(child: Center(child: _layout())),
        if (widget.id == 'perf.slide')
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, child) => Transform.translate(offset: Offset(12 * math.sin(_motion.value * 2 * math.pi), 0), child: child),
                child: _layout(),
              ),
            ),
          ),
      ],
    );
  }
}

class PerfMotion extends StatefulWidget {
  const PerfMotion({super.key, required this.clock});

  final Animation<double> clock;

  @override
  State<PerfMotion> createState() => _PerfMotionState();
}

class _PerfMotionState extends State<PerfMotion> {
  static const Duration step = Duration(milliseconds: 400);
  final List<GlobalKey> _pressed = [for (var i = 0; i < 4; i++) GlobalKey()];
  final Set<int> _down = {};
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(step, (_) => _advance());
  }

  void _advance() {
    if (!mounted) return;
    _tick++;
    for (var i = 0; i < _pressed.length; i++) {
      if ((_tick + i) % 3 == 0) {
        _pointer(i, down: true);
      } else if ((_tick + i) % 3 == 2) {
        _pointer(i, down: false);
      }
    }
    setState(() {});
  }

  void _pointer(int index, {required bool down}) {
    final box = _pressed[index].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || down == _down.contains(index)) return;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    final pointer = 900 + index;
    GestureBinding.instance.handlePointerEvent(
      down ? PointerDownEvent(pointer: pointer, position: position) : PointerUpEvent(pointer: pointer, position: position),
    );
    if (down) {
      _down.add(index);
    } else {
      _down.remove(index);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final index in _down.toList()) {
      _pointer(index, down: false);
    }
    super.dispose();
  }

  Widget _pill(int index) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: GlassEffect(glass: Glass.regular.interactive(), child: SizedBox(key: _pressed[index], width: 110, height: 44)),
  );

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SizedBox(height: 44, child: Row(mainAxisSize: MainAxisSize.min, children: children)),
  );

  @override
  Widget build(BuildContext context) {
    final shown = _tick % 2 == 0;
    final merged = _tick % 4 < 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row([_pill(0), _pill(1), _pill(2)]),
        _row([
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(width: 110, height: 44, child: (i.isEven ? shown : !shown) ? const GlassEffect(child: SizedBox(width: 110, height: 44)) : null),
            ),
        ]),
        _row([
          GlassEffectContainer(
            spacing: 20,
            child: SizedBox(
              width: 366,
              height: 44,
              child: Stack(
                children: [
                  for (final x in merged ? const [70.0, 180.0, 186.0] : const [0.0, 128.0, 256.0])
                    AnimatedPositioned(duration: Duration.zero, left: x, top: 0, child: const GlassEffect(child: SizedBox(width: 110, height: 44))),
                ],
              ),
            ),
          ),
        ]),
        AnimatedBuilder(
          animation: widget.clock,
          builder: (context, child) => Transform.translate(offset: Offset(12 * math.sin(widget.clock.value * 2 * math.pi), 0), child: child),
          child: _row([for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: GlassEffect(child: SizedBox(width: 110, height: 44)))]),
        ),
        GlassEffect(glass: Glass.regular.interactive(), child: SizedBox(key: _pressed[3], width: 360, height: 200)),
      ],
    );
  }
}
