import 'dart:async';
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
  static const String shaderAsset = 'packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag';

  static double topVisibility(ScrollMetrics metrics) =>
      ((metrics.pixels - metrics.minScrollExtent) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static double bottomVisibility(ScrollMetrics metrics) =>
      ((metrics.maxScrollExtent - metrics.pixels) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static ScrollEdgeMaterial materialOf(BuildContext context, ScrollEdgeStyle style) => ScrollEdgeMaterial.resolve(
    style: style,
    brightness: GlassTheme.brightnessOf(context),
  ).withOverrides(GlassMaterialOverride.of(context));

  final ScrollEdge edge;
  final double height;
  final ScrollEdgeStyle style;
  final double visibility;
  final double? knee;
  final double capExtent;

  @override
  State<ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

class _ScrollEdgeEffectState extends State<ScrollEdgeEffect> {
  final _boxKey = GlobalKey();
  ui.FragmentShader? _shader;
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
    setState(() {
      _shader = program.fragmentShader();
    });
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

  Widget _fallback(Color tint, double maxAlpha, double blur) {
    final outer = widget.edge == ScrollEdge.top ? Alignment.topCenter : Alignment.bottomCenter;
    final inner = widget.edge == ScrollEdge.top ? Alignment.bottomCenter : Alignment.topCenter;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: outer,
        end: inner,
        colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
      ).createShader(rect),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: ColoredBox(color: tint.withValues(alpha: maxAlpha)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    final material = ScrollEdgeEffect.materialOf(context, widget.style);
    final visibility = widget.visibility.clamp(0.0, 1.0).toDouble();
    final maxAlpha = material['dim'] * visibility;
    final tint = theme.scrollEdgeTint ?? (dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    final shade = material['lineShade'];
    final shader = _shader;
    final originY = _originY;
    _scheduleMeasure();
    return IgnorePointer(
      child: SizedBox(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        child: visibility <= 0
            ? null
            : shader == null || originY == null
            ? _fallback(tint, maxAlpha, material['blur'])
            : Builder(
                builder: (context) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  shader
                    ..setFloat(0, 0)
                    ..setFloat(1, 0)
                    ..setFloat(2, widget.height * dpr)
                    ..setFloat(3, material['blur'] * dpr * visibility)
                    ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(5, originY)
                    ..setFloat(6, tint.r)
                    ..setFloat(7, tint.g)
                    ..setFloat(8, tint.b)
                    ..setFloat(9, maxAlpha)
                    ..setFloat(10, widget.knee ?? material['knee'])
                    ..setFloat(11, widget.capExtent * dpr)
                    ..setFloat(12, material['cap'] * visibility)
                    ..setFloat(13, material['capBlur'] * dpr * visibility)
                    ..setFloat(14, shade)
                    ..setFloat(15, shade)
                    ..setFloat(16, shade)
                    ..setFloat(17, material['line'] * visibility)
                    ..setFloat(18, ScrollEdgeEffect.lineWidth * dpr);
                  return ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.shader(shader),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
