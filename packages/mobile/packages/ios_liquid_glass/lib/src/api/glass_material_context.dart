import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';

GlassMaterial resolveGlassMaterial(BuildContext context, {required Glass glass, required double shorterSide}) =>
    glassMaterialResolver(context, glass: glass)(shorterSide);

GlassMaterial Function(double shorterSide) glassMaterialResolver(BuildContext context, {required Glass glass}) {
  final brightness = GlassTheme.brightnessOf(context);
  final accessibility = GlassAccessibility.of(context);
  final override = GlassMaterialOverride.scopeOf(context);
  return (side) => GlassMaterial.resolve(
    glass: glass,
    shorterSide: side,
    brightness: brightness,
    accessibility: accessibility,
  ).withOverrides(GlassMaterialOverride.valuesFor(override, side));
}
