### Task 6: Syntax highlighting (`syntaxHighlight.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/syntax_highlight.dart`
- Test: `packages/mobile/test/feature/chat/logic/syntax_highlight_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SyntaxTokenKind { plain, comment, string, number, keyword, type, addition, deletion, meta }`
  - `class SyntaxToken extends Equatable` — `text (String)`, `kind (SyntaxTokenKind)`
  - `List<SyntaxToken>? highlightCode(String code, [String? rawLanguage])`

Lightweight native tokenization. Unknown grammars return `null` and stay exact plain text — the
renderer must never rewrite code it does not understand.

Two Dart-specific notes for the implementer. First, JavaScript's `s` (dotAll) flag is spelled
`dotAll: true` on `RegExp`; the source uses `gis`, so this is `caseSensitive: false, dotAll: true`
with `allMatches` standing in for `g`. Second, `String.split(RegExp)` in Dart drops nothing but
also has no lookbehind support in older engines — Dart *does* support `(?<=\n)`, so the diff
splitter ports as written.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/syntax_highlight_test.dart` (ported from
`chat/syntaxHighlight.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/syntax_highlight.dart';

void main() {
  group('mobile Chat syntax highlighting', () {
    test('tokenizes known coding languages without changing the source', () {
      const code = 'const answer: Result = "yes"; // note';
      final tokens = highlightCode(code, 'typescript')!;

      expect(tokens.map((token) => token.text).join(), code);
      expect(tokens, contains(const SyntaxToken(text: 'const', kind: SyntaxTokenKind.keyword)));
      expect(tokens, contains(const SyntaxToken(text: 'Result', kind: SyntaxTokenKind.type)));
      expect(tokens, contains(const SyntaxToken(text: '"yes"', kind: SyntaxTokenKind.string)));
      expect(tokens, contains(const SyntaxToken(text: '// note', kind: SyntaxTokenKind.comment)));
    });

    test('colors diffs structurally and leaves unknown languages plain', () {
      expect(
        highlightCode('+added\n-removed\n', 'diff')?.map((token) => token.kind).toList(),
        [SyntaxTokenKind.addition, SyntaxTokenKind.deletion],
      );
      expect(highlightCode('opaque', 'made-up-language'), isNull);
      expect(highlightCode('opaque'), isNull);
    });

    test('resolves aliases and the language- prefix', () {
      expect(highlightCode('x = 1 # note', 'py')?.last.kind, SyntaxTokenKind.comment);
      expect(highlightCode('const x = 1', 'language-ts'), isNotNull);
    });

    test('numbers survive a round trip through hex and decimals', () {
      final tokens = highlightCode('0xFF + 1.5', 'javascript')!;
      expect(tokens.map((token) => token.text).join(), '0xFF + 1.5');
      expect(
        tokens.where((token) => token.kind == SyntaxTokenKind.number).map((token) => token.text),
        ['0xFF', '1.5'],
      );
    });
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/syntax_highlight_test.dart`
Expected: FAIL — the library does not exist.

- [x] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/syntax_highlight.dart`:

```dart
import 'package:equatable/equatable.dart';

enum SyntaxTokenKind { plain, comment, string, number, keyword, type, addition, deletion, meta }

class SyntaxToken extends Equatable {
  const SyntaxToken({required this.text, required this.kind});

  final String text;
  final SyntaxTokenKind kind;

  @override
  List<Object?> get props => [text, kind];
}

const Map<String, String> _languageAliases = {
  'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
  'ts': 'typescript', 'tsx': 'typescript',
  'py': 'python', 'rs': 'rust', 'sh': 'shell', 'bash': 'shell', 'zsh': 'shell',
  'yml': 'yaml', 'html': 'markup', 'xml': 'markup', 'md': 'markdown',
};

final Map<String, Set<String>> _keywords = {
  'javascript': _words(
      'as async await break case catch class const continue debugger default delete do else export extends finally for from function get if implements import in instanceof interface let new of package private protected public return set static super switch throw try type typeof undefined var void while with yield'),
  'typescript': _words(
      'as async await break case catch class const continue declare default delete do else enum export extends finally for from function get if implements import in infer instanceof interface keyof let namespace never new of private protected public readonly return satisfies set static super switch throw try type typeof undefined unknown var void while yield'),
  'go': _words(
      'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var'),
  'python': _words(
      'and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield'),
  'rust': _words(
      'as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while'),
  'shell': _words(
      'case do done elif else esac export fi for function if in local readonly return set then unset while'),
  'sql': _words(
      'alter and as asc begin by case commit create delete desc distinct drop else end exists from group having in index insert into is join left like limit not null on or order outer primary references right rollback select set table then union unique update values view when where'),
  'css': _words('important inherit initial revert unset var calc media supports keyframes from to'),
  'yaml': _words('true false null yes no on off'),
  'json': _words('true false null'),
};

final Set<String> _supported = {..._keywords.keys, 'diff', 'markup', 'markdown'};

final RegExp _diffLines = RegExp(r'(?<=\n)');

List<SyntaxToken>? highlightCode(String code, [String? rawLanguage]) {
  if (rawLanguage == null) return null;
  final lowered = rawLanguage.trim().toLowerCase().replaceFirst(RegExp(r'^language-'), '');
  final language = _languageAliases[lowered] ?? lowered;
  if (!_supported.contains(language)) return null;
  if (language == 'diff') return _diffTokens(code);

  final comment = ['python', 'shell', 'yaml'].contains(language)
      ? r'#[^\n]*'
      : language == 'sql'
          ? r'--[^\n]*|/\*[\s\S]*?\*/'
          : language == 'markup'
              ? r'<!--[\s\S]*?-->'
              : r'//[^\n]*|/\*[\s\S]*?\*/';
  const stringLiteral =
      r'"(?:\\.|[^"\\])*"|' "'" r'(?:\\.|[^' "'" r'\\])*' "'" r'|`(?:\\.|[^`\\])*`';
  final source = RegExp(
    '($comment)|($stringLiteral)|' r'(\b(?:0x[\da-f]+|\d+(?:\.\d+)?)\b)|(\b[A-Za-z_$][\w$]*\b)',
    caseSensitive: false,
    dotAll: true,
  );

  final keywords = _keywords[language] ?? const <String>{};
  final tokens = <SyntaxToken>[];
  var at = 0;
  for (final match in source.allMatches(code)) {
    if (match.start > at) {
      tokens.add(SyntaxToken(text: code.substring(at, match.start), kind: SyntaxTokenKind.plain));
    }
    final text = match.group(0)!;
    final kind = match.group(1) != null
        ? SyntaxTokenKind.comment
        : match.group(2) != null
            ? SyntaxTokenKind.string
            : match.group(3) != null
                ? SyntaxTokenKind.number
                : keywords.contains(text.toLowerCase())
                    ? SyntaxTokenKind.keyword
                    : RegExp(r'^[A-Z]').hasMatch(text)
                        ? SyntaxTokenKind.type
                        : SyntaxTokenKind.plain;
    tokens.add(SyntaxToken(text: text, kind: kind));
    at = match.end;
  }
  if (at < code.length) {
    tokens.add(SyntaxToken(text: code.substring(at), kind: SyntaxTokenKind.plain));
  }
  return tokens;
}

List<SyntaxToken> _diffTokens(String code) => code
    .split(_diffLines)
    .where((line) => line.isNotEmpty)
    .map(
      (line) => SyntaxToken(
        text: line,
        kind: line.startsWith('+++') ||
                line.startsWith('---') ||
                line.startsWith('@@') ||
                line.startsWith('diff ')
            ? SyntaxTokenKind.meta
            : line.startsWith('+')
                ? SyntaxTokenKind.addition
                : line.startsWith('-')
                    ? SyntaxTokenKind.deletion
                    : SyntaxTokenKind.plain,
      ),
    )
    .toList();

Set<String> _words(String value) => value.split(' ').toSet();
```

- [x] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/syntax_highlight_test.dart`
Expected: PASS. If the string-literal pattern misbehaves, check the single-quote concatenation
first — Dart raw strings cannot contain the quote character that delimits them, which is why the
literal is assembled from three pieces.

- [x] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 441/441 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port chat syntax highlighting"
```

---
