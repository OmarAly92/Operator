import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:url_launcher/url_launcher.dart';

class BlockMarkdown extends StatelessWidget {
  const BlockMarkdown({super.key, required this.text});

  final String text;

  Future<void> _openLink(BuildContext context, String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null ||
        !const ['https', 'http', 'mailto'].contains(uri.scheme)) {
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        context.showSnackBar('Could not open this link');
      }
    } on PlatformException {
      if (context.mounted) context.showSnackBar('Could not open this link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = AppTextStyle.style13Regular.copyWith(
      color: skin.textPrimary,
      height: 1.4,
    );
    return MarkdownBody(
      data: text,
      fitContent: false,
      onTapLink: (_, href, _) => _openLink(context, href),
      imageBuilder: (uri, title, alt) => TextButton.icon(
        onPressed: () => _openLink(context, uri.toString()),
        icon: const Icon(Icons.image_outlined, size: 18),
        label: AppText(
          alt?.isNotEmpty == true ? alt! : title ?? 'Open image',
          maxLines: 3,
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        h1: AppTextStyle.style16SemiBold.copyWith(
          color: skin.textPrimary,
          height: 1.35,
        ),
        h2: AppTextStyle.style15SemiBold.copyWith(
          color: skin.textPrimary,
          height: 1.4,
        ),
        h3: AppTextStyle.style14SemiBold.copyWith(
          color: skin.textPrimary,
          height: 1.4,
        ),
        h4: body.copyWith(fontWeight: FontWeight.w600),
        h5: body.copyWith(fontWeight: FontWeight.w600),
        h6: body.copyWith(fontWeight: FontWeight.w600),
        a: body.copyWith(
          color: skin.accent,
          decoration: TextDecoration.underline,
          decorationColor: skin.accent,
        ),
        strong: const TextStyle(fontWeight: FontWeight.w600),
        listBullet: body,
        blockSpacing: 8,
        listIndent: 22,
        code: AppTextStyle.mono12Regular.copyWith(
          color: skin.textPrimary,
          backgroundColor: skin.bgSurface,
          height: 1.5,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: skin.bgSurface,
          border: Border.all(color: skin.borderSubtle),
          borderRadius: BorderRadius.circular(10),
        ),
        blockquote: body.copyWith(color: skin.textSecondary),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: skin.borderDefault, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w600),
        tableBody: body,
        tableBorder: TableBorder.all(color: skin.borderSubtle),
        tableCellsPadding: const EdgeInsets.all(8),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: skin.borderSubtle)),
        ),
      ),
    );
  }
}
