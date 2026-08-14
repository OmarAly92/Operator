import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/logic/markdown_blocks.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _inline = RegExp(
  r'(\[([^\]]+)\]\((https?://[^\s)]+)\)|<(https?://[^\s>]+)>|`([^`]+)`|\*\*([^*]+)\*\*|__([^_]+)__|'
  r'~~([^~]+)~~|\*([^*\n]+)\*|_([^_\n]+)_|(https?://[^\s<]+))',
);

bool _preferredWrap = false;

class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text, this.streaming = false});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final blocks = parseBlocks(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const VerticalSpace(10),
          _block(context, skin, blocks[index]),
        ],
      ],
    );
  }

  Widget _block(BuildContext context, AppSkin skin, MarkdownBlock block) {
    switch (block) {
      case CodeBlock(:final text, :final language):
        return _CodeCard(code: text, language: language, streaming: streaming);
      case ImageBlock(:final alt, :final url):
        return _MarkdownImage(alt: alt, url: url);
      case TableBlock(:final headers, :final rows):
        return _MarkdownTable(headers: headers, rows: rows);
      case RuleBlock():
        return Container(height: 1, color: skin.borderSubtle);
      case ListBlock(:final ordered, :final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < items.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: AppText(
                        items[index].checked != null
                            ? (items[index].checked! ? '☑' : '☐')
                            : (ordered ? '${index + 1}.' : '•'),
                        style: AppTextStyle.style15Regular.copyWith(
                          color: skin.textTertiary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const HorizontalSpace(8),
                    Expanded(
                      child: _MarkdownInlineText(
                        text: items[index].text,
                        style: AppTextStyle.style16Regular.copyWith(
                          color: items[index].checked == true
                              ? skin.textTertiary
                              : skin.textPrimary,
                          height: 1.5,
                          decoration: items[index].checked == true
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case HeadingBlock(:final text, :final level):
        return _MarkdownInlineText(
          text: text,
          style:
              (level > 2
                      ? AppTextStyle.style16Bold
                      : AppTextStyle.style19SemiBold)
                  .copyWith(color: skin.textPrimary, height: 1.35),
        );
      case QuoteBlock(:final text):
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: skin.borderStrong, width: 2),
            ),
          ),
          child: _MarkdownInlineText(
            text: text,
            style: AppTextStyle.style15Regular.copyWith(
              color: skin.textSecondary,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      case ParagraphBlock(:final text):
        return _MarkdownInlineText(
          text: text,
          style: AppTextStyle.style16Regular.copyWith(
            color: skin.textPrimary,
            height: 1.5,
          ),
        );
    }
  }
}

class _MarkdownInlineText extends StatefulWidget {
  const _MarkdownInlineText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_MarkdownInlineText> createState() => _MarkdownInlineTextState();
}

class _MarkdownInlineTextState extends State<_MarkdownInlineText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final skin = context.skin;
    return SelectableText.rich(
      TextSpan(children: _spans(skin)),
      style: widget.style,
    );
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<InlineSpan> _spans(AppSkin skin) {
    final spans = <InlineSpan>[];
    var at = 0;

    for (final match in _inline.allMatches(widget.text)) {
      if (match.start > at) {
        spans.add(TextSpan(text: widget.text.substring(at, match.start)));
      }

      final url = match.group(3) ?? match.group(4) ?? match.group(11);
      if (url != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: match.group(2) ?? url,
            style: TextStyle(
              color: skin.blue,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      } else if (match.group(5) != null) {
        spans.add(
          TextSpan(
            text: match.group(5),
            style: AppTextStyle.mono13Regular.copyWith(
              color: skin.blue,
              backgroundColor: skin.bgSubtle,
            ),
          ),
        );
      } else if (match.group(6) != null || match.group(7) != null) {
        spans.add(
          TextSpan(
            text: match.group(6) ?? match.group(7),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(8) != null) {
        spans.add(
          TextSpan(
            text: match.group(8),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: match.group(9) ?? match.group(10),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      at = match.end;
    }

    if (at < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(at)));
    }
    return spans;
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}

class _CodeCard extends StatefulWidget {
  const _CodeCard({required this.code, required this.streaming, this.language});

  final String code;
  final String? language;
  final bool streaming;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> {
  late bool _wrap;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _wrap = _preferredWrap;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = HighlightedCodeText(
      code: widget.code,
      language: widget.language,
      streaming: widget.streaming,
      style: AppTextStyle.mono13Regular,
    );

    return Container(
      decoration: BoxDecoration(
        color: skin.bgColumn,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    (widget.language ?? 'code').toUpperCase(),
                    style: AppTextStyle.mono11Regular.copyWith(
                      color: skin.textTertiary,
                    ),
                  ),
                ),
                _CodeAction(
                  icon: Icons.wrap_text,
                  label: 'Wrap',
                  active: _wrap,
                  onTap: () => setState(() {
                    _preferredWrap = !_wrap;
                    _wrap = _preferredWrap;
                  }),
                ),
                _CodeAction(
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  label: _copied ? 'Copied' : 'Copy',
                  active: _copied,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 1400),
                    );
                    if (mounted) setState(() => _copied = false);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _wrap
                ? body
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CodeAction extends StatelessWidget {
  const _CodeAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = active ? skin.blue : skin.textTertiary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const HorizontalSpace(5),
            AppText(
              label,
              style: AppTextStyle.style11SemiBold.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownImage extends StatefulWidget {
  const _MarkdownImage({required this.alt, required this.url});

  final String alt;
  final String url;

  @override
  State<_MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<_MarkdownImage> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    if (_failed) {
      return SelectableText(
        'Image unavailable: ${widget.alt.isEmpty ? widget.url : widget.alt}',
        style: AppTextStyle.style12Regular.copyWith(
          color: skin.textTertiary,
          fontStyle: FontStyle.italic,
        ),
        maxLines: 2,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: skin.bgColumn,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 420),
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _failed = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
          if (widget.alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: SelectableText(
                widget.alt,
                style: AppTextStyle.style10Regular.copyWith(
                  color: skin.textTertiary,
                ),
                maxLines: 2,
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget cell(String value, {bool header = false}) => Container(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: SelectableText(
        value,
        style: header
            ? AppTextStyle.style12Bold.copyWith(color: skin.textPrimary)
            : AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
        maxLines: 3,
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: skin.borderSubtle),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: skin.bgSubtle,
              child: Row(
                children: [
                  for (final header in headers) cell(header, header: true),
                ],
              ),
            ),
            for (final row in rows)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: skin.borderSubtle)),
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < headers.length; index++)
                      cell(index < row.length ? row[index] : ''),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
