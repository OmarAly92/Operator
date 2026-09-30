import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';
import 'package:ios_liquid_glass/src/material/scroll_edge_material.dart';

enum ScrollEdge { top, bottom }

class ScrollEdgeEffect extends StatefulWidget {
  const ScrollEdgeEffect({
    super.key,
    required this.edge,
    required this.height,
    this.style = ScrollEdgeStyle.automatic,
    this.visibility = 1,
    this.knee,
    this.capExtent = 0,
  });

  static const double fadeExtent = 16;
  static const double lineWidth = 1;
  static const int softLevels = 8;
  static const int rampStops = 24;
  static const String shaderAsset = 'packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_mask.frag';

  static double topVisibility(ScrollMetrics metrics) =>
      ((metrics.pixels - metrics.minScrollExtent) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static double bottomVisibility(ScrollMetrics metrics) =>
      ((metrics.maxScrollExtent - metrics.pixels) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static ScrollEdgeMaterial materialOf(BuildContext context, ScrollEdgeStyle style) => ScrollEdgeMaterial.resolve(
    style: style,
    brightness: GlassTheme.brightnessOf(context),
  ).withOverrides(GlassMaterialOverride.of(context));

  static double weightAt(double distance, double height, double knee) {
    final t = 1 - (distance / height).clamp(0.0, 1.0);
    if (knee <= 0) return t > 0.0001 ? 1 : 0;
    final x = (t / knee).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double capWeightAt(double distance, double capExtent) {
    if (capExtent <= 0) return 0;
    final x = ((distance - capExtent * 0.6) / (capExtent * 0.4)).clamp(0.0, 1.0);
    return 1 - x * x * (3 - 2 * x);
  }

  static List<ScrollEdgeLevel> levels({required double blur, required double knee, required double capBlur, required double capExtent}) {
    final bands = <ScrollEdgeLevel>[];
    if (blur > 0) {
      if (knee <= 0) {
        bands.add(ScrollEdgeLevel(sigma: blur, low: 0, high: 0));
      } else {
        for (var k = 1; k <= softLevels; k++) {
          final target = blur * k / softLevels;
          final previous = blur * (k - 1) / softLevels;
          bands.add(ScrollEdgeLevel(sigma: math.sqrt(target * target - previous * previous), low: (k - 1) / softLevels, high: k / softLevels));
        }
      }
    }
    if (capExtent > 0 && capBlur > 0) bands.add(ScrollEdgeLevel(sigma: capBlur, low: 0, high: 0, cap: true));
    return bands;
  }

  final ScrollEdge edge;
  final double height;
  final ScrollEdgeStyle style;
  final double visibility;
  final double? knee;
  final double capExtent;

  @override
  State<ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

@immutable
class ScrollEdgeLevel {
  const ScrollEdgeLevel({required this.sigma, required this.low, required this.high, this.cap = false});

  final double sigma;
  final double low;
  final double high;
  final bool cap;

  bool get uniform => !cap && high <= low;

  double weightAt(double distance, double height, double knee, double capExtent) {
    if (cap) return ScrollEdgeEffect.capWeightAt(distance, capExtent);
    if (uniform) return distance < height ? 1 : 0;
    final w = ScrollEdgeEffect.weightAt(distance, height, knee);
    return ((w - low) / (high - low)).clamp(0.0, 1.0);
  }
}

class _ScrollEdgeEffectState extends State<ScrollEdgeEffect> {
  final _boxKey = GlobalKey();
  ui.FragmentProgram? _program;
  final List<ui.FragmentShader> _shaders = [];
  double? _originY;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      unawaited(_loadProgram());
    }
  }

  Future<void> _loadProgram() async {
    final ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset(ScrollEdgeEffect.shaderAsset);
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() => _program = program);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _boxKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final newOriginY = box.localToGlobal(Offset.zero).dy * dpr;
      if (_originY != newOriginY) {
        setState(() => _originY = newOriginY);
      }
    });
  }

  ui.FragmentShader _shaderAt(int index) {
    while (_shaders.length <= index) {
      _shaders.add(_program!.fragmentShader());
    }
    return _shaders[index];
  }

  @override
  void dispose() {
    for (final shader in _shaders) {
      shader.dispose();
    }
    super.dispose();
  }

  Widget _level(int index, ScrollEdgeLevel level, double knee, double reach) {
    final blur = ui.ImageFilter.blur(sigmaX: level.sigma, sigmaY: level.sigma, tileMode: TileMode.mirror);
    final originY = _originY;
    if (level.uniform) {
      return ClipRect(child: BackdropFilter(filter: blur, child: const SizedBox.expand()));
    }
    if (_program != null && originY != null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final shader = _shaderAt(index)
        ..setFloat(0, 0)
        ..setFloat(1, 0)
        ..setFloat(2, originY)
        ..setFloat(3, widget.height * reach * dpr)
        ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
        ..setFloat(5, knee)
        ..setFloat(6, level.low)
        ..setFloat(7, level.high)
        ..setFloat(8, widget.capExtent * dpr)
        ..setFloat(9, level.cap ? 1 : 0);
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(outer: ui.ImageFilter.shader(shader), inner: blur),
          child: const SizedBox.expand(),
        ),
      );
    }
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => _ramp(rect, (distance) => level.weightAt(distance, rect.height * reach, knee, widget.capExtent)),
      child: ClipRect(child: BackdropFilter(filter: blur, child: const SizedBox.expand())),
    );
  }

  ui.Shader _ramp(Rect rect, double Function(double distance) alphaAt) {
    const count = ScrollEdgeEffect.rampStops;
    final stops = [for (var i = 0; i <= count; i++) i / count];
    final colors = [for (final stop in stops) const Color(0xFFFFFFFF).withValues(alpha: alphaAt(stop * rect.height))];
    final fromTop = widget.edge == ScrollEdge.top;
    return ui.Gradient.linear(
      fromTop ? rect.topCenter : rect.bottomCenter,
      fromTop ? rect.bottomCenter : rect.topCenter,
      colors,
      stops,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    final material = ScrollEdgeEffect.materialOf(context, widget.style);
    final visibility = widget.visibility.clamp(0.0, 1.0).toDouble();
    final tint = theme.scrollEdgeTint ?? (dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    final knee = widget.knee ?? material['knee'];
    final blurKnee = knee <= 0 ? 0.0 : widget.knee ?? material['blurKnee'];
    final blurReach = widget.knee == null ? material['blurReach'] : 1.0;
    final levels = ScrollEdgeEffect.levels(
      blur: material['blur'] * visibility,
      knee: blurKnee,
      capBlur: material['capBlur'] * visibility,
      capExtent: widget.capExtent,
    );
    _scheduleMeasure();
    return IgnorePointer(
      child: SizedBox(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        child: visibility <= 0
            ? null
            : Stack(
                fit: StackFit.expand,
                children: [
                  for (final (index, level) in levels.indexed) _level(index, level, blurKnee, blurReach),
                  CustomPaint(
                    painter: ScrollEdgeTintPainter(
                      fromTop: widget.edge == ScrollEdge.top,
                      tint: tint,
                      dim: material['dim'] * visibility,
                      knee: knee,
                      cap: material['cap'] * visibility,
                      capExtent: widget.capExtent,
                      line: material['line'] * visibility,
                      lineShade: material['lineShade'],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ScrollEdgeTintPainter extends CustomPainter {
  const ScrollEdgeTintPainter({
    required this.fromTop,
    required this.tint,
    required this.dim,
    required this.knee,
    required this.cap,
    required this.capExtent,
    required this.line,
    required this.lineShade,
  });

  final bool fromTop;
  final Color tint;
  final double dim;
  final double knee;
  final double cap;
  final double capExtent;
  final double line;
  final double lineShade;

  double alphaAt(double distance, double height) {
    final w = ScrollEdgeEffect.weightAt(distance, height, knee);
    final c = ScrollEdgeEffect.capWeightAt(distance, capExtent);
    return (dim * w) * (1 - c) + cap * c;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const count = ScrollEdgeEffect.rampStops;
    final stops = [for (var i = 0; i <= count; i++) i / count];
    final colors = [for (final stop in stops) tint.withValues(alpha: alphaAt(stop * size.height, size.height).clamp(0.0, 1.0))];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          fromTop ? rect.topCenter : rect.bottomCenter,
          fromTop ? rect.bottomCenter : rect.topCenter,
          colors,
          stops,
        ),
    );
    if (line > 0) {
      final top = fromTop ? size.height - ScrollEdgeEffect.lineWidth : 0.0;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, ScrollEdgeEffect.lineWidth),
        Paint()..color = Color.from(alpha: line.clamp(0.0, 1.0), red: lineShade, green: lineShade, blue: lineShade),
      );
    }
  }

  @override
  bool shouldRepaint(ScrollEdgeTintPainter old) =>
      old.fromTop != fromTop ||
      old.tint != tint ||
      old.dim != dim ||
      old.knee != knee ||
      old.cap != cap ||
      old.capExtent != capExtent ||
      old.line != line ||
      old.lineShade != lineShade;
}
