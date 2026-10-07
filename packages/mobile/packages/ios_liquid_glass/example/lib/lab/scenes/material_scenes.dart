import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_launch.dart';
import '../glass_lab_marker.dart';
import 'lab_parts.dart';

const Color labAccent = Color(0xFF1ACB64);

sealed class MaterialScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'material.regular': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: const [
        LabBlock(width: 150, height: 44),
        LabBlock(width: 250, height: 88),
        LabBlock(width: 360, height: 200),
      ],
    ),
    'material.clear': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 64,
      children: const [
        LabBlock(width: 250, height: 88, glass: Glass.clear),
        GlassDimming(child: LabBlock(width: 250, height: 88, glass: Glass.clear)),
      ],
    ),
    'material.tinted': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        LabBlock(width: 250, height: 88, glass: Glass.regular.tint(labAccent)),
        GlassLabMarker(
          'tinted.run',
          child: GlassEffect(
            glass: Glass.regular.tint(labAccent).interactive(),
            child: const SizedBox(
              width: 78,
              height: 37,
              child: GlassForeground(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.play_arrow_rounded, size: 20), SizedBox(width: 6), Text('Run', style: TextStyle(fontSize: 17))],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    'material.interactive': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [GlassLabMarker('glass', child: LabBlock(width: 250, height: 88, glass: Glass.regular.interactive()))],
    ),
    'material.shapes': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 40,
      children: [
        const LabBlock(width: 250, height: 60),
        const LabBlock(width: 250, height: 88, shape: GlassShape.rect(16)),
        SizedBox(
          width: 300,
          height: 180,
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0x4DFFFFFF), borderRadius: BorderRadius.circular(40)),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: GlassEffect(shape: GlassShape.rect(28), child: SizedBox.expand()),
            ),
          ),
        ),
      ],
    ),
    'material.union': (launch) => UnionScene(backdrop: launch.backdrop),
    'material.morph': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        GlassLabMarker(
          'morph',
          child: GlassEffect(
            glass: Glass.regular.interactive(),
            shape: const GlassShape.circle(),
            child: const SizedBox.square(dimension: 56, child: GlassForeground(child: Icon(Icons.add, size: 22))),
          ),
        ),
      ],
    ),
    'material.flip': (launch) => const Stack(
      children: [
        Positioned.fill(child: GlassLabScrollBackdrop()),
        Positioned.fill(
          child: IgnorePointer(
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(height: 180),
                  LabBlock(width: 150, height: 44),
                  Spacer(),
                  LabBlock(width: 360, height: 200),
                  SizedBox(height: 96),
                  LabBlock(width: 150, height: 44),
                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    'material.edge.soft': (launch) => const EdgeScene(style: ScrollEdgeStyle.soft),
    'material.edge.hard': (launch) => const EdgeScene(style: ScrollEdgeStyle.hard),
    'material.edge.automatic': (launch) => const EdgeScene(style: ScrollEdgeStyle.automatic),
  };
}

class EdgeScene extends StatefulWidget {
  const EdgeScene({super.key, required this.style});

  static const double offset = 300;
  static const double barHeight = 54;
  static const double itemHeight = 44;

  final ScrollEdgeStyle style;

  @override
  State<EdgeScene> createState() => _EdgeSceneState();
}

class _EdgeSceneState extends State<EdgeScene> {
  final _controller = ScrollController();
  bool _scrolled = false;

  Widget _scrollOnce(BuildContext context, Widget child, int? frame, bool synchronous) {
    if (frame != null && !_scrolled) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpTo(EdgeScene.offset);
      });
    }
    return child;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      child: Stack(
        children: [
          Positioned.fill(
            child: ScrollUnderBars(
              style: widget.style,
              child: GlassLabMarker(
                'scroll.content',
                child: SingleChildScrollView(
                  controller: _controller,
                  padding: EdgeInsets.only(top: top + EdgeScene.barHeight),
                  child: Image.file(
                    GlassLabBackdrop.file('scroll'),
                    width: width,
                    fit: BoxFit.fitWidth,
                    frameBuilder: _scrollOnce,
                    errorBuilder: (_, _, _) => SizedBox(width: width, height: 2000, child: const ColoredBox(color: GlassLabBackdrop.missingColor)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: EdgeScene.itemHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const GlassForeground(child: Text('Edge', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                Positioned(
                  right: 16,
                  child: GlassEffect(
                    child: const SizedBox(
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Center(child: GlassForeground(child: Text('Edit', style: TextStyle(fontSize: 17)))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UnionScene extends StatefulWidget {
  const UnionScene({super.key, required this.backdrop});

  static const List<IconData> symbols = [Icons.star, Icons.favorite, Icons.bolt, Icons.eco];

  final String backdrop;

  @override
  State<UnionScene> createState() => _UnionSceneState();
}

class _UnionSceneState extends State<UnionScene> {
  final GlassNamespace _namespace = GlassNamespace();

  @override
  Widget build(BuildContext context) {
    return LabCentered(
      backdrop: widget.backdrop,
      children: [
        GlassEffectContainer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, icon) in UnionScene.symbols.indexed) ...[
                if (index > 0) const SizedBox(width: 16),
                GlassEffect(
                  union: GlassEffectUnion(index < 2 ? 'first' : 'second', _namespace),
                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: 24))),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
