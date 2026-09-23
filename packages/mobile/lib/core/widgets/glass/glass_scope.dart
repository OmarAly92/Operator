import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

class GlassScope extends StatelessWidget {
  const GlassScope({super.key, required this.variant, required this.size, required this.child});

  final GlassVariant variant;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassLayer(
      settings: GlassStyle.resolve(
        skin: context.skin,
        variant: variant,
        size: size,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: child,
    );
  }
}
