import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';

void main() {
  group('kControlKeys', () {
    test('offers exactly the eight keys the row divides its width between', () {
      expect(kControlKeys, hasLength(8));
      expect(
        kControlKeys.map((key) => key.label).toList(),
        ['esc', 'tab', '^C', '←', '↑', '↓', '→', '↵'],
      );
    });

    test('carries the escape sequences the PTY expects', () {
      final byLabel = {for (final key in kControlKeys) key.label: key.sequence};
      expect(byLabel['esc'], '\x1b');
      expect(byLabel['tab'], '\t');
      expect(byLabel['^C'], '\x03');
      expect(byLabel['←'], '\x1b[D');
      expect(byLabel['↑'], '\x1b[A');
      expect(byLabel['↓'], '\x1b[B');
      expect(byLabel['→'], '\x1b[C');
      expect(byLabel['↵'], '\r');
    });

    test('labels every key for accessibility', () {
      expect(kControlKeys.every((key) => key.hint.isNotEmpty), isTrue);
    });
  });
}
