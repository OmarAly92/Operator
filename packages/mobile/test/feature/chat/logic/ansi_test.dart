import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/ansi.dart';

void main() {
  group('mobile Chat terminal text', () {
    test('removes ANSI and applies carriage-return redraws', () {
      expect(stripAnsi('\x1b[32mok\x1b[0m 12%\rready'), 'ready%');
    });

    test('leaves text with no control bytes untouched', () {
      expect(stripAnsi(''), '');
      expect(stripAnsi('plain output'), 'plain output');
    });

    test('applies backspace overwrites per line', () {
      expect(stripAnsi('abc\b\bXY'), 'aXY');
      expect(stripAnsi('one\ntwo\rTWO'), 'one\nTWO');
    });

    test('drops an escape sequence cut off by the end of a chunk', () {
      expect(stripAnsi('done\x1b['), 'done');
    });

    test('reads structured historical output without crashing', () {
      expect(
        commandOutputText({
          'metadata': {'text': 'done'},
        }),
        'done',
      );
      expect(commandOutputText(null), '');
      expect(commandOutputText('\x1b[31mred\x1b[0m'), 'red');
      expect(commandOutputText({'count': 2}), '{\n  "count": 2\n}');
    });

    test('keeps terminal input meaningful', () {
      expect(caretNotation('\x03\n'), '^C\n');
      expect(caretNotation('a\tb'), 'a\tb');
      expect(caretNotation('\x7f'), '^?');
    });
  });
}
