import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_scene_parts.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

sealed class LabMaterialScenes {
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
        LabBlock(width: 250, height: 88, variant: GlassVariant.clear),
        _DimmedClear(),
      ],
    ),
    'material.tinted': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        const LabBlock(width: 250, height: 88, variant: GlassVariant.prominent),
        GlassButton.label(label: 'Run', icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
      ],
    ),
    'material.interactive': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: const [GlassLabMarker('glass', child: LabBlock(width: 250, height: 88, pressable: true))],
    ),
    'material.edge.soft': (launch) => const _EdgeScene(),
    'material.edge.hard': (launch) => const _EdgeScene(),
    'material.edge.automatic': (launch) => const _EdgeScene(),
  };
}

class _DimmedClear extends StatelessWidget {
  const _DimmedClear();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        SizedBox(
          width: 250,
          height: 88,
          child: DecoratedBox(
            decoration: ShapeDecoration(color: Color(0x59000000), shape: StadiumBorder()),
          ),
        ),
        LabBlock(width: 250, height: 88, variant: GlassVariant.clear),
      ],
    );
  }
}

class _EdgeScene extends StatelessWidget {
  const _EdgeScene();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: GlobalAppbar.sub(
        titleText: 'Edge',
        actions: [GlassButton.label(label: 'Edit', onPressed: () {})],
      ),
      body: const Stack(
        children: [
          Positioned.fill(child: GlassLabScrollBackdrop()),
          Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 140)),
        ],
      ),
    );
  }
}
