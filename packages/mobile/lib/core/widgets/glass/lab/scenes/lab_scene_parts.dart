import 'package:flutter/material.dart';
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
