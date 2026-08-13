import 'dart:convert';

final RegExp _escape = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*(?:[@-~]|$)|\][\s\S]*?(?:\x07|\x1B\\|$)|[P^_X][\s\S]*?(?:\x1B\\|\x07|$)|[@-Z\\-_]|[ -/]+[0-~])',
);
final RegExp _leftoverControls = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

const List<String> _outputKeys = ['output', 'text', 'error', 'metadata'];

String stripAnsi(String text) {
  if (text.isEmpty ||
      (!text.contains('\x1B') &&
          !text.contains('\r') &&
          !text.contains('\b') &&
          !text.contains('\x07'))) {
    return text;
  }

  final withoutEscapes = text.replaceAll(_escape, '');
  if (!withoutEscapes.contains('\r') && !withoutEscapes.contains('\b')) {
    return withoutEscapes.replaceAll(_leftoverControls, '');
  }
  return withoutEscapes
      .split('\n')
      .map(_overwrite)
      .join('\n')
      .replaceAll(_leftoverControls, '');
}

String caretNotation(String text) {
  final output = StringBuffer();
  for (final character in text.runes) {
    if (character == 0x0A || character == 0x09) {
      output.writeCharCode(character);
    } else if (character < 0x20) {
      output.write('^${String.fromCharCode(character + 64)}');
    } else {
      output.write(character == 0x7F ? '^?' : String.fromCharCode(character));
    }
  }
  return output.toString();
}

String commandOutputText(dynamic raw) {
  if (raw is String) return stripAnsi(raw);
  if (raw is! Map) return '';
  for (final key in _outputKeys) {
    final text = commandOutputText(raw[key]);
    if (text.isNotEmpty) return text;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(raw);
  } catch (_) {
    return '';
  }
}

String _overwrite(String line) {
  if (!line.contains('\r') && !line.contains('\b')) return line;
  var output = '';
  var column = 0;
  for (final character in line.split('')) {
    if (character == '\r') {
      column = 0;
      continue;
    }
    if (character == '\b') {
      column = column > 0 ? column - 1 : 0;
      continue;
    }
    output = column < output.length
        ? output.substring(0, column) + character + output.substring(column + 1)
        : output + character;
    column += 1;
  }
  return output;
}
