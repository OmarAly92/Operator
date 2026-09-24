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

  Widget _fallback(Color bg) {
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
          child: ColoredBox(color: bg.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.skin.bgBase;
    final program = _program;
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: program == null
            ? _fallback(bg)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, widget.height);
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final shader = program.fragmentShader()
                    ..setFloat(0, size.width * dpr)
                    ..setFloat(1, size.height * dpr)
                    ..setFloat(2, 18 * dpr)
                    ..setFloat(3, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(4, bg.r)
                    ..setFloat(5, bg.g)
                    ..setFloat(6, bg.b)
                    ..setFloat(7, 0.55);
                  ui.ImageFilter filter;
                  try {
                    filter = ui.ImageFilter.shader(shader);
                  } on UnsupportedError {
                    return _fallback(bg);
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
