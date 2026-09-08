import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';

class AppContainer extends StatelessWidget {
  const AppContainer({
    super.key,
    required this.child,
    this.constraints,
    this.onTap,
    this.padding,
    this.margin,
    this.disable = false,
    this.border,
    this.borderRadius,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.hapticsOnTap = true,
    this.pressScale = false,
  });

  final Widget child;
  final BoxConstraints? constraints;
  final void Function()? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool disable;
  final BoxBorder? border;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final bool hapticsOnTap;

  /// Applies the prototype's `CARD_SURFACE` press feedback
  /// (`AppMotion.pressScaleDefault` + `AppMotion.spring`,
  /// `docs/design/components.md`) when this container is tappable. Opt-in —
  /// defaults to `false` so existing non-card call sites (buttons, rows,
  /// chips with their own press treatment) are unaffected.
  final bool pressScale;

  void Function()? get _onTap {
    final handler = onTap;
    if (handler == null) return null;
    if (!hapticsOnTap) return handler;
    return () {
      Haptics.tap();
      handler();
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: backgroundColor ?? context.skin.bgSurface,
      borderRadius: borderRadius ?? BorderRadius.circular(AppConstants.radiusButton),
      child: AppInkWell(
        borderRadius: borderRadius ?? BorderRadius.circular(AppConstants.radiusButton),
        onTap: _onTap,
        child: Container(
          width: width,
          height: height,
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          constraints: constraints,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(AppConstants.radiusButton),
            border: border,
            boxShadow: boxShadow,
          ),
          child: child,
        ),
      ),
    );

    return Opacity(
      opacity: disable ? .5 : 1,
      child: Padding(
        padding: margin ?? EdgeInsets.zero,
        child: pressScale && onTap != null
            ? PressScale(child: content)
            : content,
      ),
    );
  }
}
