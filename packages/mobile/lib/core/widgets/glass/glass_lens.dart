import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class GlassLens extends StatefulWidget {
  const GlassLens({super.key});

  static const double interiorShade = 0.032;
  static const double edgeShade = 0.065;
  static const double edgeShadeDepth = 8;

  static const double minify = 1.127;
  static const double dispersion = 0.012;
  static const double capStart = 3;
  static const double capEnd = 9;
  static const double capScale = 0.95;
  static const double rimWidth = 0.7;
  static const double rimGlowWidth = 1.2;
  static const double rimAlpha = 0.43;
  static const double rimBottomAlpha = 0.45;
  static const double rimTopAlpha = 0.45;
  static const double rimTopGlow = 0.44;

  static Future<ui.FragmentProgram?>? _program;

  static Future<ui.FragmentProgram?> _load() => _program ??= () async {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    try {
      return await ui.FragmentProgram.fromAsset('shaders/tab_lens.frag');
    } on Object {
      return null;
    }
  }();

  @override
  State<GlassLens> createState() => _GlassLensState();
}

class _GlassLensState extends State<GlassLens> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    unawaited(
      GlassLens._load().then((program) {
        if (!mounted || program == null) return;
        setState(() => _shader = program.fragmentShader());
      }),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LensPaint(shader: _shader, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
}

class _LensPaint extends LeafRenderObjectWidget {
  const _LensPaint({required this.shader, required this.devicePixelRatio});

  final ui.FragmentShader? shader;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLens(shader, devicePixelRatio);

  @override
  void updateRenderObject(BuildContext context, _RenderLens renderObject) {
    renderObject
      ..shader = shader
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderLens extends RenderBox {
  _RenderLens(this._shader, this._devicePixelRatio);

  ui.FragmentShader? _shader;
  set shader(ui.FragmentShader? value) {
    if (identical(_shader, value)) return;
    _shader = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRRectLayer>();
  final _filter = LayerHandle<BackdropFilterLayer>();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => _shader != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final rrect = RRect.fromRectAndRadius(offset & size, Radius.circular(size.shortestSide / 2));
    final shader = _shader;
    if (shader == null) {
      _clip.layer = null;
      context.canvas.drawRRect(
        rrect.deflate(GlassLens.rimWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = GlassLens.rimWidth
          ..color = const Color(0xFFFFFFFF).withValues(alpha: GlassLens.rimAlpha),
      );
      return;
    }
    final global = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    final dpr = _devicePixelRatio;
    shader
      ..setFloat(0, 0)
      ..setFloat(1, 0)
      ..setFloat(2, global.left * dpr)
      ..setFloat(3, global.top * dpr)
      ..setFloat(4, global.width * dpr)
      ..setFloat(5, global.height * dpr)
      ..setFloat(6, GlassLens.minify + GlassLens.dispersion)
      ..setFloat(7, GlassLens.minify)
      ..setFloat(8, GlassLens.minify - GlassLens.dispersion)
      ..setFloat(9, GlassLens.capStart * dpr)
      ..setFloat(10, GlassLens.capEnd * dpr)
      ..setFloat(11, GlassLens.capScale)
      ..setFloat(12, GlassLens.rimWidth * dpr)
      ..setFloat(13, GlassLens.rimGlowWidth * dpr)
      ..setFloat(14, GlassLens.rimAlpha)
      ..setFloat(15, GlassLens.rimBottomAlpha)
      ..setFloat(16, GlassLens.rimTopAlpha)
      ..setFloat(17, GlassLens.rimTopGlow)
      ..setFloat(18, GlassLens.interiorShade)
      ..setFloat(19, GlassLens.edgeShade)
      ..setFloat(20, GlassLens.edgeShadeDepth * dpr);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.shortestSide / 2)),
      (context, offset) {
        final layer = _filter.layer ??= BackdropFilterLayer();
        layer.filter = ui.ImageFilter.shader(shader);
        context.pushLayer(layer, (context, offset) {}, offset);
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _filter.layer = null;
    super.dispose();
  }
}
