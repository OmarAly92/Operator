import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';

class GlassEffectContainer extends StatelessWidget {
  const GlassEffectContainer({super.key, this.spacing = 20, this.glass = Glass.regular, this.side = 88, required this.child});

  final double spacing;
  final Glass glass;
  final double side;
  final Widget child;

  static Glass? glassOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ContainerScope>()?.glass;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final material = resolveGlassMaterial(context, glass: glass, shorterSide: side);
        return LiquidGlassLayer(
          settings: material.toSettings(tint: glass.tintColor),
          child: LiquidGlassBlendGroup(blend: spacing, child: _ContainerScope(glass: glass, child: child)),
        );
      },
    );
  }
}

class _ContainerScope extends InheritedWidget {
  const _ContainerScope({required this.glass, required super.child});

  final Glass glass;

  @override
  bool updateShouldNotify(_ContainerScope oldWidget) => oldWidget.glass != glass;
}
