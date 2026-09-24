import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

enum ScrollEdge { top, bottom }

class ScrollEdgeEffect extends StatefulWidget {
  const ScrollEdgeEffect({super.key, required this.edge, required this.height});

  final ScrollEdge edge;
  final double height;

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

  Widget _fallback(double maxAlpha) {
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
          child: ColoredBox(color: const Color(0xFF000000).withValues(alpha: maxAlpha)),
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
    final dark = context.skin.themeMode == ThemeMode.dark;
    final maxAlpha = dark ? 0.2 : 0.15;
    final shader = _shader;
    final originY = _originY;
    _scheduleMeasure();
    return IgnorePointer(
      child: SizedBox(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        child: shader == null || originY == null
            ? _fallback(maxAlpha)
            : Builder(
                builder: (context) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  shader
                    ..setFloat(0, 0)
                    ..setFloat(1, 0)
                    ..setFloat(2, widget.height * dpr)
                    ..setFloat(3, 18 * dpr)
                    ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(5, originY)
                    ..setFloat(6, 0)
                    ..setFloat(7, 0)
                    ..setFloat(8, 0)
                    ..setFloat(9, maxAlpha);
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
