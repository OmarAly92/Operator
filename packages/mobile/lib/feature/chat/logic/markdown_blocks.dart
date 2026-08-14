import 'package:equatable/equatable.dart';

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.+)$');
final RegExp _image = RegExp(r'^!\[([^\]]*)\]\((https?://[^\s)]+)\)\s*$');
final RegExp _rule = RegExp(r'^\s*(---+|\*\*\*+)\s*$');
final RegExp _listItem = RegExp(r'^\s*(?:(\d+)\.|[-*+])\s+(.+)$');
final RegExp _quote = RegExp(r'^>\s?');
final RegExp _task = RegExp(r'^\[([ xX])\]\s+(.+)$');
final RegExp _divider = RegExp(r'^:?-{3,}:?$');

sealed class MarkdownBlock extends Equatable {
  const MarkdownBlock();

  @override
  List<Object?> get props => [];
}

final class ParagraphBlock extends MarkdownBlock {
  const ParagraphBlock({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

final class HeadingBlock extends MarkdownBlock {
  const HeadingBlock({required this.text, required this.level});

  final String text;
  final int level;

  @override
  List<Object?> get props => [text, level];
}

final class QuoteBlock extends MarkdownBlock {
  const QuoteBlock({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

class ListItem extends Equatable {
  const ListItem({required this.text, this.checked});

  final String text;
  final bool? checked;

  @override
  List<Object?> get props => [text, checked];
}

final class ListBlock extends MarkdownBlock {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<ListItem> items;

  @override
  List<Object?> get props => [ordered, items];
}

final class CodeBlock extends MarkdownBlock {
  const CodeBlock({required this.text, this.language});

  final String text;
  final String? language;

  @override
  List<Object?> get props => [text, language];
}

final class TableBlock extends MarkdownBlock {
  const TableBlock({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  List<Object?> get props => [headers, rows];
}

final class ImageBlock extends MarkdownBlock {
  const ImageBlock({required this.alt, required this.url});

  final String alt;
  final String url;

  @override
  List<Object?> get props => [alt, url];
}

final class RuleBlock extends MarkdownBlock {
  const RuleBlock();
}

List<MarkdownBlock> parseBlocks(String input) {
  final lines = input.replaceAll('\r', '').split('\n');
  final blocks = <MarkdownBlock>[];
  var paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(ParagraphBlock(text: paragraph.join('\n').trim()));
    }
    paragraph = <String>[];
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.startsWith('```')) {
      flushParagraph();
      final language = line.substring(3).trim();
      final code = <String>[];
      for (i += 1; i < lines.length && !lines[i].startsWith('```'); i++) {
        code.add(lines[i]);
      }
      blocks.add(
        CodeBlock(
          language: language.isEmpty ? null : language,
          text: code.join('\n'),
        ),
      );
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        HeadingBlock(level: heading.group(1)!.length, text: heading.group(2)!),
      );
      continue;
    }

    final image = _image.firstMatch(line.trim());
    if (image != null) {
      flushParagraph();
      blocks.add(ImageBlock(alt: image.group(1)!, url: image.group(2)!));
      continue;
    }

    if (line.contains('|') &&
        i + 1 < lines.length &&
        _isTableDivider(lines[i + 1])) {
      flushParagraph();
      final headers = _tableCells(line);
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length &&
          lines[i].contains('|') &&
          lines[i].trim().isNotEmpty) {
        rows.add(_tableCells(lines[i]));
        i++;
      }
      i--;
      blocks.add(TableBlock(headers: headers, rows: rows));
      continue;
    }

    if (_rule.hasMatch(line)) {
      flushParagraph();
      blocks.add(const RuleBlock());
      continue;
    }

    final item = _listItem.firstMatch(line);
    if (item != null) {
      flushParagraph();
      final ordered = item.group(1) != null;
      final items = [_taskItem(item.group(2)!)];
      while (i + 1 < lines.length) {
        final next = _listItem.firstMatch(lines[i + 1]);
        if (next == null || (next.group(1) != null) != ordered) {
          break;
        }
        items.add(_taskItem(next.group(2)!));
        i += 1;
      }
      blocks.add(ListBlock(ordered: ordered, items: items));
      continue;
    }

    if (_quote.hasMatch(line)) {
      flushParagraph();
      final quote = [line.replaceFirst(_quote, '')];
      while (i + 1 < lines.length && _quote.hasMatch(lines[i + 1])) {
        quote.add(lines[++i].replaceFirst(_quote, ''));
      }
      blocks.add(QuoteBlock(text: quote.join('\n')));
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
    } else {
      paragraph.add(line);
    }
  }

  flushParagraph();
  return blocks;
}

ListItem _taskItem(String value) {
  final task = _task.firstMatch(value);
  if (task == null) {
    return ListItem(text: value);
  }
  return ListItem(
    text: task.group(2)!,
    checked: task.group(1)!.toLowerCase() == 'x',
  );
}

bool _isTableDivider(String value) {
  final cells = _tableCells(value);
  return cells.isNotEmpty && cells.every(_divider.hasMatch);
}

List<String> _tableCells(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^\|'), '')
    .replaceFirst(RegExp(r'\|$'), '')
    .split('|')
    .map((cell) => cell.trim())
    .toList();
