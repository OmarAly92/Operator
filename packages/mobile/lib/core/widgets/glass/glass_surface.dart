import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

enum GlassShapeKind { capsule, circle, rect, roundedRect }

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.kind,
    required this.size,
    required this.child,
    this.radius = 0,
    this.grouped = false,
    this.pressable = false,
    this.enabled = true,
    this.glowAlpha = 0.35,
    this.variant = GlassVariant.regular,
  });

  static const Key outlineKey = ValueKey('glass-surface-outline');
  static const Key rimKey = ValueKey('glass-surface-rim');
  static const double rimWidth = 0.5;
  static const double pressedScale = 1.08;

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool grouped;
  final bool pressable;
  final bool enabled;
  final double glowAlpha;
  final GlassVariant variant;
  final Widget child;

  LiquidShape get _shape => switch (kind) {
    GlassShapeKind.capsule => const LiquidRoundedRectangle(borderRadius: 999),
    GlassShapeKind.circle => const LiquidOval(),
    GlassShapeKind.rect => LiquidRoundedSuperellipse(borderRadius: radius),
    GlassShapeKind.roundedRect => LiquidRoundedRectangle(borderRadius: radius),
  };

  OutlinedBorder get _outline => switch (kind) {
    GlassShapeKind.capsule => const StadiumBorder(),
    GlassShapeKind.circle => const CircleBorder(),
    GlassShapeKind.rect => RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(radius))),
    GlassShapeKind.roundedRect => RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radius))),
  };

  @override
  Widget build(BuildContext context) {
    final glass = _glass(context);
    return pressable ? _PressLift(enabled: enabled, child: glass) : glass;
  }

  Widget _glass(BuildContext context) {
    final skin = context.skin;
    final highContrast = MediaQuery.highContrastOf(context);
    final glowing = pressable && enabled
        ? GlassGlow(
            glowColor: const Color(0xFFFFFFFF).withValues(alpha: glowAlpha),
            child: child,
          )
        : child;
    final content = highContrast
        ? DecoratedBox(
            key: outlineKey,
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: _outline.copyWith(side: BorderSide(color: skin.borderStrong)),
            ),
            child: glowing,
          )
        : skin.glassRim.a > 0 && variant != GlassVariant.prominent && variant != GlassVariant.chrome
        ? DecoratedBox(
            key: rimKey,
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: _outline.copyWith(
                side: BorderSide(color: skin.glassRim, width: rimWidth),
              ),
            ),
            child: glowing,
          )
        : glowing;
    final shadows = GlassStyle.shadows(skin, size: size, variant: variant);
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

class _PressLift extends StatefulWidget {
  const _PressLift({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PressLift> createState() => _PressLiftState();
}

class _PressLiftState extends State<_PressLift> {
  bool _pressed = false;

  void _set(bool value) {
    if (value && !widget.enabled) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _PressLift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !still ? GlassSurface.pressedScale : 1.0,
        duration: AppMotion.slow,
        curve: AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
