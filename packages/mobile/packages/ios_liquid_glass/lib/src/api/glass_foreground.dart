import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';

class GlassForeground extends StatelessWidget {
  const GlassForeground({super.key, required this.child});

  static const Color dark = Color(0xFFFFFFFF);
  static const Color light = Color(0xFF000000);
  static const Color tinted = Color(0xFFFFFFFF);

  final Widget child;

  static Color colorOf(BuildContext context) {
    final glass = GlassEffectScope.maybeOf(context);
    if (glass != null && glass.kind == GlassKind.regular && glass.tintColor != null) return tinted;
    return GlassTheme.brightnessOf(context) == Brightness.dark ? dark : light;
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context);
    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: IconTheme.merge(data: IconThemeData(color: color), child: child),
    );
  }
}
