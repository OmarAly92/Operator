import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

class GlassBarItem extends StatelessWidget {
  const GlassBarItem({super.key, required this.child, this.extent});

  final Widget child;
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final resolvedExtent = extent ?? GlassMetrics.hitTarget;
    return GlassSurface(
      kind: GlassShapeKind.capsule,
      size: resolvedExtent,
      child: Theme(
        data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: resolvedExtent,
              minHeight: resolvedExtent,
              maxHeight: resolvedExtent,
            ),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}
