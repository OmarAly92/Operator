import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

class GlassBarItem extends StatelessWidget {
  const GlassBarItem({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      kind: GlassShapeKind.capsule,
      size: GlassMetrics.hitTarget,
      child: Theme(
        data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: GlassMetrics.hitTarget,
              minHeight: GlassMetrics.hitTarget,
              maxHeight: GlassMetrics.hitTarget,
            ),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}
