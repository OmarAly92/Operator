import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

class GlassScope extends StatelessWidget {
  const GlassScope({super.key, required this.variant, required this.size, required this.child});

  final GlassVariant variant;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GlassEffectContainer(spacing: 20, glass: glassForVariant(context, variant), side: size, child: child);
}
