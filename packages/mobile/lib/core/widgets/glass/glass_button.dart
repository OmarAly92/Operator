import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassButton extends StatefulWidget {
  const GlassButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.prominent = false,
    this.foreground,
    this.diameter,
    this.haptic = Haptics.tap,
  })  : label = null,
        compact = false;

  const GlassButton.label({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
    this.compact = false,
    this.haptic = Haptics.tap,
  })  : semanticLabel = null,
        foreground = null,
        diameter = null;

  static const double pressedScale = 1.08;

  final IconData? icon;
  final String? label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool compact;
  final Color? foreground;
  final double? diameter;
  final VoidCallback haptic;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (value && !_enabled) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant GlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _pressed) setState(() => _pressed = false);
  }

  void _handleTap() {
    widget.haptic();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final foreground = widget.foreground ?? (widget.prominent ? skin.onGlassProminent : skin.accentText);
    final isIcon = widget.label == null;
    final capsuleHeight = widget.compact ? GlassMetrics.compactButtonHeight : GlassMetrics.hitTarget;
    final horizontalPadding = widget.compact ? GlassMetrics.compactLabelButtonPadding : GlassMetrics.labelButtonPadding;
    final iconDiameter = widget.diameter ?? GlassMetrics.hitTarget;
    final iconGlyphSize = ((22 * iconDiameter / GlassMetrics.hitTarget) * 2).round() / 2;
    final content = isIcon
        ? SizedBox.square(
            dimension: iconDiameter,
            child: Icon(widget.icon, size: iconGlyphSize, color: foreground, semanticLabel: widget.semanticLabel),
          )
        : SizedBox(
            height: capsuleHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  AppText(widget.label!, style: AppTextStyle.style17Regular.copyWith(color: foreground)),
                ],
              ),
            ),
          );
    final scaled = AnimatedScale(
      scale: _pressed && !reduceMotion ? GlassButton.pressedScale : 1.0,
      duration: AppMotion.slow,
      curve: AppMotion.spring,
      child: GlassSurface(
        kind: isIcon ? GlassShapeKind.circle : GlassShapeKind.capsule,
        size: isIcon ? iconDiameter : capsuleHeight,
        variant: widget.prominent ? GlassVariant.prominent : GlassVariant.regular,
        child: _enabled
            ? GlassGlow(
                glowColor: const Color(0xFFFFFFFF).withValues(alpha: widget.prominent ? 0.25 : 0.35),
                child: content,
              )
            : content,
      ),
    );
    final tappable = widget.compact ? SizedBox(height: GlassMetrics.hitTarget, child: Center(child: scaled)) : scaled;
    return Semantics(
      button: true,
      enabled: _enabled,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _handleTap : null,
          child: tappable,
        ),
      ),
    );
  }
}
