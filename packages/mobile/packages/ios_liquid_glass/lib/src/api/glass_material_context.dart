import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';

GlassMaterial resolveGlassMaterial(BuildContext context, {required Glass glass, required double shorterSide}) =>
    GlassMaterial.resolve(
      glass: glass,
      shorterSide: shorterSide,
      brightness: GlassTheme.brightnessOf(context),
      accessibility: GlassAccessibility.of(context),
    ).withOverrides(GlassMaterialOverride.forSide(context, shorterSide));
