import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

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
    this.glowAlpha = 0.35,
    this.variant = GlassVariant.regular,
  });

  static const double pressedScale = 1.08;

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool pressable;
  final bool enabled;
  final double glowAlpha;
  final GlassVariant variant;
  final Widget child;

  GlassShape get shape => switch (kind) {
    GlassShapeKind.capsule => const GlassShape.capsule(),
    GlassShapeKind.circle => const GlassShape.circle(),
    GlassShapeKind.rect => GlassShape.superellipse(radius),
    GlassShapeKind.roundedRect => GlassShape.rect(radius),
  };

  @override
  Widget build(BuildContext context) {
    final content = pressable && enabled
        ? GlassGlow(glowColor: const Color(0xFFFFFFFF).withValues(alpha: glowAlpha), child: child)
        : child;
    final glass = GlassEffect(glass: glassForVariant(context, variant), shape: shape, sideHint: size, child: content);
    return pressable ? _PressLift(enabled: enabled, child: glass) : glass;
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
