import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_marker.dart';

class LabCentered extends StatelessWidget {
  const LabCentered({super.key, required this.backdrop, required this.children, this.gap = 48, this.bottom});

  final String backdrop;
  final List<Widget> children;
  final double gap;
  final Widget? bottom;

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
        if (bottom != null) Positioned(left: 0, right: 0, bottom: 120, child: Center(child: bottom)),
      ],
    );
  }
}

class LabBlock extends StatelessWidget {
  const LabBlock({super.key, required this.width, required this.height, this.glass = Glass.regular, this.shape = const GlassShape.capsule()});

  final double width;
  final double height;
  final Glass glass;
  final GlassShape shape;

  @override
  Widget build(BuildContext context) =>
      GlassEffect(glass: glass, shape: shape, child: SizedBox(width: width, height: height));
}

class LabButton extends StatelessWidget {
  const LabButton({super.key, required this.title, required this.id, this.onTap});

  final String title;
  final String id;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassLabMarker(
      id,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const ShapeDecoration(color: Color(0xFFFFFFFF), shape: StadiumBorder()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF000000))),
          ),
        ),
      ),
    );
  }
}
