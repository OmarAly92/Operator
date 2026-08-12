import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.textColor,
    this.borderRadius,
    required this.onPressed,
    this.isExpand = false,
    this.padding,
    this.isLoading = false,
    this.fixedSize,
    this.icon,
    this.trailingIcon,
  });

  const PrimaryButton.expand({
    super.key,
    required this.text,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.textColor,
    this.borderRadius,
    required this.onPressed,
    this.isExpand = true,
    this.padding,
    this.isLoading = false,
    this.fixedSize,
    this.icon,
    this.trailingIcon,
  });

  final String text;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? textColor;
  final Size? fixedSize;
  final bool isExpand;
  final bool isLoading;
  final BorderRadiusGeometry? borderRadius;
  final void Function()? onPressed;
  final Widget? icon;
  final Widget? trailingIcon;

  @override
  Widget build(BuildContext context) {
    if (isExpand) {
      return SizedBox(
        height: fixedSize?.height ?? 50,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: buildButtonStyleFrom(context),
                onPressed: isLoading ? () {} : onPressed,
                child: isLoading
                    ? Center(
                        child: SpinKitThreeBounce(
                          color: foregroundColor ?? context.skin.onAccent,
                          size: 35,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            icon!,
                            const HorizontalSpace(8),
                          ],
                          AppText(
                            text,
                            style:
                                textStyle ??
                                AppTextStyle.style17Medium.copyWith(
                                  color: textColor ?? context.skin.onAccent,
                                ),
                          ),
                          if (trailingIcon != null) ...[
                            const HorizontalSpace(8),
                            trailingIcon!,
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    } else {
      return ElevatedButton(
        style: buildButtonStyleFrom(context),
        onPressed: isLoading ? () {} : onPressed,
        child: isLoading
            ? SpinKitThreeBounce(
                color: foregroundColor ?? context.skin.onAccent,
                size: 35,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  AppText(
                    text,
                    style:
                        textStyle ??
                        AppTextStyle.style17Medium.copyWith(
                          color: textColor ?? context.skin.onAccent,
                        ),
                  ),
                  if (trailingIcon != null) ...[
                    const HorizontalSpace(8),
                    trailingIcon!,
                  ],
                ],
              ),
      );
    }
  }

  ButtonStyle buildButtonStyleFrom(BuildContext context) {
    return ElevatedButton.styleFrom(
      padding: padding,
      fixedSize: fixedSize ?? const Size.fromHeight(48),
      foregroundColor: foregroundColor ?? context.skin.onAccent,
      backgroundColor: backgroundColor ?? context.skin.accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
    );
  }
}
