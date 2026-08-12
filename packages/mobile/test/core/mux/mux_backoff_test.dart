import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';

void main() {
  group('MuxBackoff', () {
    test('starts at one second', () {
      expect(MuxBackoff.initialMs, 1000);
    });

    test('doubles on every step', () {
      expect(MuxBackoff.next(1000), 2000);
      expect(MuxBackoff.next(2000), 4000);
      expect(MuxBackoff.next(4000), 8000);
    });

    test('caps at fifteen seconds', () {
      expect(MuxBackoff.next(8000), 15000);
      expect(MuxBackoff.next(15000), 15000);
    });
  });
}
