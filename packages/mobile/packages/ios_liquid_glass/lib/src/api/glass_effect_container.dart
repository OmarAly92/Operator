import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect.dart';
import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
import 'package:meta/meta.dart';

class GlassEffectContainer extends StatefulWidget {
  const GlassEffectContainer({super.key, this.spacing = 8, this.glass = Glass.regular, this.side, required this.child});

  final double spacing;
  final Glass glass;
  final double? side;
  final Widget child;

  static Glass? glassOf(BuildContext context) => scopeOf(context)?.glass;

  @internal
  static GlassContainerScope? scopeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassContainerScope>();

  @override
  State<GlassEffectContainer> createState() => _GlassEffectContainerState();
}

class _GlassEffectContainerState extends State<GlassEffectContainer> with SingleTickerProviderStateMixin {
  late final GlassMotionCoordinator _coordinator = GlassMotionCoordinator(vsync: this);
  GlassMaterialSource? _material;
  GlassOverlayGhosts? _overlay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final overlay = GlassOverlayGhosts.of(context);
    if (identical(overlay, _overlay)) return;
    _overlay?.release();
    _overlay = overlay?..retain();
  }

  @override
  void deactivate() {
    _coordinator.depart(_overlay?.coordinator);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _coordinator.stay();
  }

  @override
  void dispose() {
    _coordinator.dispose();
    _material?.dispose();
    _overlay?.release();
    _overlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _coordinator.spacingTo(widget.spacing, scope: GlassAnimationScope.maybeOf(context));
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final resolve = glassMaterialResolver(context, glass: widget.glass);
        final tint = widget.glass.tintColor;
        final fixed = widget.side;
        final material = _material ??= GlassMaterialSource(resolve: resolve, tint: tint, side: fixed ?? GlassEffect.fallbackSide);
        material.configure(resolve: resolve, tint: tint);
        if (fixed != null) material.resize(fixed, exact: true);
        _coordinator.followMaterial = fixed == null ? material : null;
        return GlassCoordinatorSpace(
          coordinator: _coordinator,
          child: LiquidGlassLayer(
            settings: material.settings,
            settingsSource: material,
            child: LiquidGlassBlendGroup(
              blend: widget.spacing,
              blendMotion: _coordinator.spacing,
              child: GlassContainerScope(
                glass: widget.glass,
                material: material,
                coordinator: _coordinator,
                child: Stack(
                  alignment: Alignment.topLeft,
                  fit: StackFit.passthrough,
                  clipBehavior: Clip.none,
                  children: [widget.child, Positioned.fill(child: GlassGhostHost(coordinator: _coordinator))],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

@internal
class GlassContainerScope extends InheritedWidget {
  const GlassContainerScope({super.key, required this.glass, required this.material, required this.coordinator, required super.child});

  final Glass glass;
  final GlassMaterialSource material;
  final GlassMotionCoordinator coordinator;

  @override
  bool updateShouldNotify(GlassContainerScope oldWidget) =>
      oldWidget.glass != glass || oldWidget.material != material || oldWidget.coordinator != coordinator;
}
