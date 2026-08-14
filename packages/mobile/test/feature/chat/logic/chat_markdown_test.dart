import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/markdown_blocks.dart';

void main() {
  group('mobile Chat markdown blocks', () {
    test('keeps GFM tables, tasks and remote images structured', () {
      final blocks = parseBlocks(
        [
          '| File | State |',
          '| --- | --- |',
          '| app.ts | changed |',
          '',
          '- [x] inspect',
          '- [ ] test',
          '',
          '![result](https://example.com/result.png)',
        ].join('\n'),
      );

      expect(
        blocks[0],
        const TableBlock(
          headers: ['File', 'State'],
          rows: [
            ['app.ts', 'changed'],
          ],
        ),
      );
      expect(
        blocks[1],
        const ListBlock(
          ordered: false,
          items: [
            ListItem(text: 'inspect', checked: true),
            ListItem(text: 'test', checked: false),
          ],
        ),
      );
      expect(
        blocks[2],
        const ImageBlock(alt: 'result', url: 'https://example.com/result.png'),
      );
    });

    test('keeps fenced code with its language and its blank lines', () {
      final blocks = parseBlocks(
        '```dart\nvoid main() {}\n\nfinal x = 1;\n```',
      );

      expect(
        blocks.single,
        const CodeBlock(
          language: 'dart',
          text: 'void main() {}\n\nfinal x = 1;',
        ),
      );
    });

    test('reads headings, quotes, ordered lists and rules', () {
      expect(
        parseBlocks('## Findings').single,
        const HeadingBlock(text: 'Findings', level: 2),
      );
      expect(
        parseBlocks('> one\n> two').single,
        const QuoteBlock(text: 'one\ntwo'),
      );
      expect(
        parseBlocks('1. first\n2. second').single,
        const ListBlock(
          ordered: true,
          items: [
            ListItem(text: 'first'),
            ListItem(text: 'second'),
          ],
        ),
      );
      expect(parseBlocks('---').single, const RuleBlock());
    });

    test('leaves unknown syntax as readable paragraph text', () {
      expect(
        parseBlocks(':::note\nhi\n:::').single,
        const ParagraphBlock(text: ':::note\nhi\n:::'),
      );
    });
  });
}
