import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required super.child,
    this.useFake = false,
    this.visibility,
    this.settingsSource,
    super.key,
  });

  final LiquidGlassSettings settings;

  final Animation<double>? visibility;

  final GlassMaterialSource? settingsSource;

  final bool useFake;

  static LiquidGlassRenderScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    assert(
      scope != null,
      'No liquid glass renderer found in context. '
      'Make sure to wrap your liquid glass widgets in a LiquidGlassLayer.',
    );
    return scope!;
  }

  /// Returns the nearest [LiquidGlassRenderScope] from the widget tree,
  /// or `null` if there is none.
  static LiquidGlassRenderScope? maybeOf(
    BuildContext context, {
    bool watch = true,
  }) {
    if (watch) {
      return context
          .dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    } else {
      return context.getInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    }
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassRenderScope ||
        oldWidget.settings != settings ||
        oldWidget.useFake != useFake ||
        oldWidget.visibility != visibility ||
        oldWidget.settingsSource != settingsSource;
  }
}
