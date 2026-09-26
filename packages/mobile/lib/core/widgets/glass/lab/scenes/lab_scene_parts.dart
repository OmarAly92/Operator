import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';

class LabCentered extends StatelessWidget {
  const LabCentered({super.key, required this.backdrop, required this.children, this.gap = 48});

  final String backdrop;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: backdrop)),
        SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LabBlock extends StatelessWidget {
  const LabBlock({
    super.key,
    required this.width,
    required this.height,
    this.variant = GlassVariant.regular,
    this.pressable = false,
  });

  final double width;
  final double height;
  final GlassVariant variant;
  final bool pressable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GlassSurface(
        kind: GlassShapeKind.capsule,
        size: height,
        variant: variant,
        pressable: pressable,
        child: const SizedBox.expand(),
      ),
    );
  }
}
