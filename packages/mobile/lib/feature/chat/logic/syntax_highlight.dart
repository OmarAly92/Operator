import 'package:equatable/equatable.dart';

enum SyntaxTokenKind {
  plain,
  comment,
  string,
  number,
  keyword,
  type,
  addition,
  deletion,
  meta,
}

class SyntaxToken extends Equatable {
  const SyntaxToken({required this.text, required this.kind});

  final String text;
  final SyntaxTokenKind kind;

  @override
  List<Object?> get props => [text, kind];
}

const Map<String, String> _languageAliases = {
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rs': 'rust',
  'sh': 'shell',
  'bash': 'shell',
  'zsh': 'shell',
  'yml': 'yaml',
  'html': 'markup',
  'xml': 'markup',
  'md': 'markdown',
};

final Map<String, Set<String>> _keywords = {
  'javascript': _words(
    'as async await break case catch class const continue debugger default delete do else export extends finally for from function get if implements import in instanceof interface let new of package private protected public return set static super switch throw try type typeof undefined var void while with yield',
  ),
  'typescript': _words(
    'as async await break case catch class const continue declare default delete do else enum export extends finally for from function get if implements import in infer instanceof interface keyof let namespace never new of private protected public readonly return satisfies set static super switch throw try type typeof undefined unknown var void while yield',
  ),
  'go': _words(
    'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var',
  ),
  'python': _words(
    'and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield',
  ),
  'rust': _words(
    'as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while',
  ),
  'shell': _words(
    'case do done elif else esac export fi for function if in local readonly return set then unset while',
  ),
  'sql': _words(
    'alter and as asc begin by case commit create delete desc distinct drop else end exists from group having in index insert into is join left like limit not null on or order outer primary references right rollback select set table then union unique update values view when where',
  ),
  'css': _words(
    'important inherit initial revert unset var calc media supports keyframes from to',
  ),
  'yaml': _words('true false null yes no on off'),
  'json': _words('true false null'),
};

final Set<String> _supported = {
  ..._keywords.keys,
  'diff',
  'markup',
  'markdown',
};

final RegExp _diffLines = RegExp(r'(?<=\n)');

List<SyntaxToken>? highlightCode(String code, [String? rawLanguage]) {
  if (rawLanguage == null) return null;
  final lowered = rawLanguage.trim().toLowerCase().replaceFirst(
    RegExp(r'^language-'),
    '',
  );
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
      r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`''';
  final source = RegExp(
    '($comment)|($stringLiteral)|'
    r'(\b(?:0x[\da-f]+|\d+(?:\.\d+)?)\b)|(\b[A-Za-z_$][\w$]*\b)',
    caseSensitive: false,
    dotAll: true,
  );

  final keywords = _keywords[language] ?? const <String>{};
  final tokens = <SyntaxToken>[];
  var at = 0;
  for (final match in source.allMatches(code)) {
    if (match.start > at) {
      tokens.add(
        SyntaxToken(
          text: code.substring(at, match.start),
          kind: SyntaxTokenKind.plain,
        ),
      );
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
    tokens.add(
      SyntaxToken(text: code.substring(at), kind: SyntaxTokenKind.plain),
    );
  }
  return tokens;
}

List<SyntaxToken> _diffTokens(String code) => code
    .split(_diffLines)
    .map(
      (line) => SyntaxToken(
        text: line,
        kind:
            line.startsWith('+++') ||
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
