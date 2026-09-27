import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_control_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_material_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_navigation_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_presentation_scenes.dart';

typedef GlassLabSceneBuilder = Widget Function(GlassLabLaunch launch);

sealed class GlassLabRegistry {
  static final Map<String, GlassLabSceneBuilder> scenes = {
    ...LabMaterialScenes.scenes,
    ...LabNavigationScenes.scenes,
    ...LabPresentationScenes.scenes,
    ...LabControlScenes.scenes,
  };

  static Widget build(GlassLabLaunch launch) {
    if (launch.bare) return GlassLabBackdrop(id: launch.backdrop);
    final builder = scenes[launch.scene];
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
                child: Text(
                  'missing: ${launch.scene}',
                  style: AppTextStyle.style15SemiBold.copyWith(color: const Color(0xFF000000)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
