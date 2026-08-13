### Task 5: Markdown block parser (`markdownBlocks.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/markdown_blocks.dart`
- Test: `packages/mobile/test/feature/chat/logic/chat_markdown_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `sealed class MarkdownBlock extends Equatable` with
    `ParagraphBlock(text)`, `HeadingBlock(text, level)`, `QuoteBlock(text)`,
    `ListBlock(ordered, items)` where `items` is `List<ListItem>`,
    `CodeBlock(language, text)`, `TableBlock(headers, rows)`, `ImageBlock(alt, url)`,
    `RuleBlock()`
  - `class ListItem extends Equatable` — `text (String)`, `checked (bool?)`
  - `List<MarkdownBlock> parseBlocks(String input)`

RN models blocks as a discriminated union; Dart's equivalent is a sealed class, which also gives
Task 20's renderer an exhaustive `switch` with no default branch to forget.

Unknown syntax stays readable paragraph text. The renderer never hides content because a provider
used syntax it does not know.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/chat_markdown_test.dart` (ported from
`chat/ChatMarkdown.test.ts`, extended to pin the block kinds the renderer switches on):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/markdown_blocks.dart';

void main() {
  group('mobile Chat markdown blocks', () {
    test('keeps GFM tables, tasks and remote images structured', () {
      final blocks = parseBlocks([
        '| File | State |',
        '| --- | --- |',
        '| app.ts | changed |',
        '',
        '- [x] inspect',
        '- [ ] test',
        '',
        '![result](https://example.com/result.png)',
      ].join('\n'));

      expect(
        blocks[0],
        const TableBlock(headers: ['File', 'State'], rows: [['app.ts', 'changed']]),
      );
      expect(
        blocks[1],
        const ListBlock(
          ordered: false,
          items: [ListItem(text: 'inspect', checked: true), ListItem(text: 'test', checked: false)],
        ),
      );
      expect(blocks[2], const ImageBlock(alt: 'result', url: 'https://example.com/result.png'));
    });

    test('keeps fenced code with its language and its blank lines', () {
      final blocks = parseBlocks('```dart\nvoid main() {}\n\nfinal x = 1;\n```');
      expect(blocks.single, const CodeBlock(language: 'dart', text: 'void main() {}\n\nfinal x = 1;'));
    });

    test('reads headings, quotes, ordered lists and rules', () {
      expect(parseBlocks('## Findings').single, const HeadingBlock(text: 'Findings', level: 2));
      expect(parseBlocks('> one\n> two').single, const QuoteBlock(text: 'one\ntwo'));
      expect(
        parseBlocks('1. first\n2. second').single,
        const ListBlock(ordered: true, items: [ListItem(text: 'first'), ListItem(text: 'second')]),
      );
      expect(parseBlocks('---').single, const RuleBlock());
    });

    test('leaves unknown syntax as readable paragraph text', () {
      expect(parseBlocks(':::note\nhi\n:::').single, const ParagraphBlock(text: ':::note\nhi\n:::'));
    });
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/chat_markdown_test.dart`
Expected: FAIL — the library does not exist.

- [x] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/markdown_blocks.dart`:

```dart
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
    if (paragraph.isNotEmpty) blocks.add(ParagraphBlock(text: paragraph.join('\n').trim()));
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
      blocks.add(CodeBlock(language: language.isEmpty ? null : language, text: code.join('\n')));
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(HeadingBlock(level: heading.group(1)!.length, text: heading.group(2)!));
      continue;
    }

    final image = _image.firstMatch(line.trim());
    if (image != null) {
      flushParagraph();
      blocks.add(ImageBlock(alt: image.group(1)!, url: image.group(2)!));
      continue;
    }

    if (line.contains('|') && i + 1 < lines.length && _isTableDivider(lines[i + 1])) {
      flushParagraph();
      final headers = _tableCells(line);
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
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
        if (next == null || (next.group(1) != null) != ordered) break;
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
  if (task == null) return ListItem(text: value);
  return ListItem(text: task.group(2)!, checked: task.group(1)!.toLowerCase() == 'x');
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
```

- [x] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/chat_markdown_test.dart`
Expected: PASS.

- [x] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 437/437 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the chat markdown block parser"
```

---
