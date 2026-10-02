import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';

class GlassDimming extends StatelessWidget {
  const GlassDimming({super.key, this.opacity = 0.35, this.shape = const GlassShape.capsule(), required this.child});

  final double opacity;
  final GlassShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: const Color(0xFF000000).withValues(alpha: opacity), shape: shape.border),
    child: child,
  );
}
