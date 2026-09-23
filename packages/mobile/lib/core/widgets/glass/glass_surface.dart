import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

enum GlassShapeKind { capsule, circle, rect }

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.kind,
    required this.size,
    required this.child,
    this.radius = 0,
    this.grouped = false,
    this.variant = GlassVariant.regular,
  });

  static const Key outlineKey = ValueKey('glass-surface-outline');

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool grouped;
  final GlassVariant variant;
  final Widget child;

  LiquidShape get _shape => switch (kind) {
        GlassShapeKind.capsule => const LiquidRoundedRectangle(borderRadius: 999),
        GlassShapeKind.circle => const LiquidOval(),
        GlassShapeKind.rect => LiquidRoundedSuperellipse(borderRadius: radius),
      };

  OutlinedBorder get _outline => switch (kind) {
        GlassShapeKind.capsule => const StadiumBorder(),
        GlassShapeKind.circle => const CircleBorder(),
        GlassShapeKind.rect => RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(radius))),
      };

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final highContrast = MediaQuery.highContrastOf(context);
    final content = highContrast
        ? DecoratedBox(
            key: outlineKey,
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(shape: _outline.copyWith(side: BorderSide(color: skin.borderStrong))),
            child: child,
          )
        : child;
    final shadows = GlassStyle.shadows(skin);
    final settings = GlassStyle.resolve(skin: skin, variant: variant, size: size, highContrast: highContrast);
    if (variant != GlassVariant.regular) {
      return LiquidGlass.withOwnLayer(shape: _shape, shadows: shadows, settings: settings, child: content);
    }
    if (grouped) {
      return LiquidGlass.grouped(shape: _shape, shadows: shadows, child: content);
    }
    return LiquidGlass.auto(shape: _shape, shadows: shadows, settings: settings, child: content);
  }
}
