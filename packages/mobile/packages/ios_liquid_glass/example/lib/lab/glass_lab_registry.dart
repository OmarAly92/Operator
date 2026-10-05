import 'package:flutter/material.dart';

import 'glass_lab_backdrop.dart';
import 'glass_lab_launch.dart';
import 'glass_lab_marker.dart';
import 'scenes/material_scenes.dart';
import 'scenes/motion_scenes.dart';
import 'scenes/perf_scenes.dart';

sealed class GlassLabRegistry {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes, ...MotionScenes.scenes};
  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {...PerfScenes.scenes, ...MotionScenes.tools};

  static Widget build(GlassLabLaunch launch) {
    if (launch.bare) return GlassLabBackdrop(id: launch.backdrop);
    final builder = scenes[launch.scene] ?? tools[launch.scene];
    return builder == null ? GlassLabMissing(launch: launch) : builder(launch);
  }
}

class GlassLabMissing extends StatelessWidget {
  const GlassLabMissing({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: launch.backdrop)),
        Center(
          child: GlassLabMarker(
            'scene.missing',
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('missing: ${launch.scene}', style: const TextStyle(fontSize: 15, color: Color(0xFF000000))),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
