import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

enum ScrollEdge { top, bottom }

class ScrollEdgeEffect extends StatefulWidget {
  const ScrollEdgeEffect({
    super.key,
    required this.edge,
    required this.height,
    this.visibility = 1,
    this.knee,
    this.capExtent = 0,
  });

  static const double fadeExtent = 16;
  static const double capRadius = 12;

  static double topVisibility(ScrollMetrics metrics) =>
      ((metrics.pixels - metrics.minScrollExtent) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static double bottomVisibility(ScrollMetrics metrics) =>
      ((metrics.maxScrollExtent - metrics.pixels) / fadeExtent).clamp(0.0, 1.0).toDouble();

  final ScrollEdge edge;
  final double height;
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
      program = await ui.FragmentProgram.fromAsset('shaders/scroll_edge_blur.frag');
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

  double _maxAlpha(bool dark) {
    return switch ((dark, widget.edge)) {
      (false, ScrollEdge.top) => 0.78,
      (false, ScrollEdge.bottom) => 0.7,
      (true, ScrollEdge.top) => 0.6,
      (true, ScrollEdge.bottom) => 0.49,
    };
  }

  double _capAlpha(bool dark) => dark ? 0.88 : 0.94;

  double get _knee => widget.knee ?? (widget.edge == ScrollEdge.top ? 0.45 : 0.8);

  Widget _fallback(Color tint, double maxAlpha) {
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
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
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
    final skin = context.skin;
    final dark = skin.themeMode == ThemeMode.dark;
    final visibility = widget.visibility.clamp(0.0, 1.0).toDouble();
    final maxAlpha = _maxAlpha(dark) * visibility;
    final tint = skin.scrollEdgeTint;
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
            ? _fallback(tint, maxAlpha)
            : Builder(
                builder: (context) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  shader
                    ..setFloat(0, 0)
                    ..setFloat(1, 0)
                    ..setFloat(2, widget.height * dpr)
                    ..setFloat(3, 4 * dpr * visibility)
                    ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(5, originY)
                    ..setFloat(6, tint.r)
                    ..setFloat(7, tint.g)
                    ..setFloat(8, tint.b)
                    ..setFloat(9, maxAlpha)
                    ..setFloat(10, _knee)
                    ..setFloat(11, widget.capExtent * dpr)
                    ..setFloat(12, _capAlpha(dark) * visibility)
                    ..setFloat(13, ScrollEdgeEffect.capRadius * dpr * visibility);
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
