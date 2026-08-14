import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/chat/logic/syntax_highlight.dart';

class HighlightedCodeText extends StatelessWidget {
  const HighlightedCodeText({
    super.key,
    required this.code,
    this.language,
    this.streaming = false,
    this.style,
  });

  final String code;
  final String? language;
  final bool streaming;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final base = (style ?? AppTextStyle.mono13Regular).copyWith(
      color: style?.color ?? skin.textPrimary,
      height: 1.5,
    );
    final tokens = streaming ? null : highlightCode(code, language);

    if (tokens == null) return SelectableText(code, style: base);

    return SelectableText.rich(
      TextSpan(
        children: [
          for (final token in tokens)
            TextSpan(
              text: token.text,
              style: base.copyWith(color: _tokenColor(skin, token.kind)),
            ),
        ],
      ),
      style: base,
    );
  }

  Color _tokenColor(AppSkin skin, SyntaxTokenKind kind) {
    switch (kind) {
      case SyntaxTokenKind.comment:
        return skin.textFaint;
      case SyntaxTokenKind.string:
      case SyntaxTokenKind.addition:
        return skin.green;
      case SyntaxTokenKind.number:
        return skin.orange;
      case SyntaxTokenKind.keyword:
        return skin.purple;
      case SyntaxTokenKind.type:
      case SyntaxTokenKind.meta:
        return skin.blue;
      case SyntaxTokenKind.deletion:
        return skin.red;
      case SyntaxTokenKind.plain:
        return skin.textPrimary;
    }
  }
}
