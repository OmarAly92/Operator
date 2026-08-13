import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/short_label.dart';

void main() {
  group('shortLabel', () {
    test('leaves a short value untouched', () {
      expect(shortLabel('my-app'), 'my-app');
      expect(shortLabel('12345678901234567890'), '12345678901234567890');
    });

    test('keeps the head and the tail so two projects stay distinguishable', () {
      final a = shortLabel('my-app_98d163a851');
      final b = shortLabel('my-app_11ffffffff');
      expect(a, isNot(b));
    });

    test('middle-truncates to the maximum length', () {
      final got = shortLabel('abcdefghijklmnopqrstuvwxyz');
      expect(got.length, 20);
      expect(got.contains('…'), isTrue);
      expect(got.startsWith('abcdefghij'), isTrue);
      expect(got.endsWith('rstuvwxyz'), isTrue);
    });

    test('honours a caller-supplied maximum', () {
      expect(shortLabel('abcdefghij', max: 5).length, 5);
    });
  });
}
