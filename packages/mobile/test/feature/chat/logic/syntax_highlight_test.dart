import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/syntax_highlight.dart';

void main() {
  group('mobile Chat syntax highlighting', () {
    test('tokenizes known coding languages without changing the source', () {
      const code = 'const answer: Result = "yes"; // note';
      final tokens = highlightCode(code, 'typescript')!;

      expect(tokens.map((token) => token.text).join(), code);
      expect(
        tokens,
        contains(
          const SyntaxToken(text: 'const', kind: SyntaxTokenKind.keyword),
        ),
      );
      expect(
        tokens,
        contains(const SyntaxToken(text: 'Result', kind: SyntaxTokenKind.type)),
      );
      expect(
        tokens,
        contains(
          const SyntaxToken(text: '"yes"', kind: SyntaxTokenKind.string),
        ),
      );
      expect(
        tokens,
        contains(
          const SyntaxToken(text: '// note', kind: SyntaxTokenKind.comment),
        ),
      );
    });

    test('colors diffs structurally and leaves unknown languages plain', () {
      expect(
        highlightCode(
          '+added\n-removed\n',
          'diff',
        )?.map((token) => token.kind).toList(),
        [SyntaxTokenKind.addition, SyntaxTokenKind.deletion],
      );
      expect(
        highlightCode(
          '+added\n-removed\n',
          'diff',
        )?.map((token) => token.text).join(),
        '+added\n-removed\n',
      );
      expect(highlightCode('opaque', 'made-up-language'), isNull);
      expect(highlightCode('opaque'), isNull);
    });

    test('resolves aliases and the language prefix', () {
      expect(
        highlightCode('x = 1 # note', 'py')?.last.kind,
        SyntaxTokenKind.comment,
      );
      expect(highlightCode('const x = 1', 'language-ts'), isNotNull);
    });

    test('numbers survive a round trip through hex and decimals', () {
      final tokens = highlightCode('0xFF + 1.5', 'javascript')!;
      expect(tokens.map((token) => token.text).join(), '0xFF + 1.5');
      expect(
        tokens
            .where((token) => token.kind == SyntaxTokenKind.number)
            .map((token) => token.text),
        ['0xFF', '1.5'],
      );
    });
  });
}
