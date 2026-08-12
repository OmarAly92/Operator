import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:flutter/material.dart';

TextStyle _resolveSkinStyle(BuildContext context, TextStyle? style) {
  if (style == null) return TextStyle(color: context.skin.textPrimary);
  if (style.color != null) return style;
  return style.copyWith(color: context.skin.textPrimary);
}

class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
  });

  final String text;
  final TextStyle? style;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: _resolveSkinStyle(context, style),
      maxLines: maxLines ?? 1,
      overflow: overflow ?? TextOverflow.ellipsis,
      textAlign: textAlign,
      textDirection: textDirection,
    );
  }
}
