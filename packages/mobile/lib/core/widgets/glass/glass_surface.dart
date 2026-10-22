import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

enum GlassShapeKind { capsule, circle, rect, roundedRect }

enum GlassVariant { regular, clear, prominent, chrome }

Glass glassForVariant(BuildContext context, GlassVariant variant) => switch (variant) {
  GlassVariant.clear => Glass.clear,
  GlassVariant.prominent => Glass.regular.tint(GlassTheme.of(context).accent),
  GlassVariant.regular || GlassVariant.chrome => Glass.regular,
};

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.kind,
    required this.size,
    required this.child,
    this.radius = 0,
    this.pressable = false,
    this.enabled = true,
    this.variant = GlassVariant.regular,
  });

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool pressable;
  final bool enabled;
  final GlassVariant variant;
  final Widget child;

  GlassShape get shape => switch (kind) {
    GlassShapeKind.capsule => const GlassShape.capsule(),
    GlassShapeKind.circle => const GlassShape.circle(),
    GlassShapeKind.rect => GlassShape.superellipse(radius),
    GlassShapeKind.roundedRect => GlassShape.rect(radius),
  };

  @override
  Widget build(BuildContext context) =>
      GlassEffect(glass: glassForVariant(context, variant).interactive(pressable && enabled), shape: shape, sideHint: size, child: child);
}
