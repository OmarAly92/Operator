import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_scene_parts.dart';

sealed class LabControlScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'button.styles': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 18,
      children: [
        for (final compact in [true, true, false, false])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassButton.label(label: 'Glass', compact: compact, onPressed: () {}),
              const SizedBox(width: 12),
              GlassButton.label(label: 'Prominent', compact: compact, prominent: true, onPressed: () {}),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassButton.icon(icon: Icons.add_rounded, onPressed: () {}),
            const SizedBox(width: 16),
            GlassButton.icon(icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
          ],
        ),
      ],
    ),
    'button.press': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 69,
      children: [
        GlassLabMarker('btn.glass', child: GlassButton.label(label: 'Glass button', onPressed: () {})),
        GlassLabMarker('btn.prominent', child: GlassButton.label(label: 'Prominent button', prominent: true, onPressed: () {})),
      ],
    ),
  };
}
