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
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProgram());
  }

  Future<void> _loadProgram() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/scroll_edge_blur.frag');
    if (!mounted) return;
    setState(() {
      _program = program;
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
  Widget build(BuildContext context) {
    final dark = context.skin.themeMode == ThemeMode.dark;
    final maxAlpha = dark ? 0.2 : 0.15;
    final program = _program;
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: program == null
            ? _fallback(maxAlpha)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, widget.height);
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final shader = program.fragmentShader()
                    ..setFloat(0, size.width * dpr)
                    ..setFloat(1, size.height * dpr)
                    ..setFloat(2, size.height * dpr)
                    ..setFloat(3, 18 * dpr)
                    ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(5, 0)
                    ..setFloat(6, 0)
                    ..setFloat(7, 0)
                    ..setFloat(8, maxAlpha);
                  ui.ImageFilter filter;
                  try {
                    filter = ui.ImageFilter.shader(shader);
                  } on UnsupportedError {
                    return _fallback(maxAlpha);
                  }
                  return ClipRect(
                    child: BackdropFilter(filter: filter, child: const SizedBox.expand()),
                  );
                },
              ),
      ),
    );
  }
}
