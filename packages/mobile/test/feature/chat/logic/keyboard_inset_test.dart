import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';

void main() {
  group('dockInset', () {
    test('owes nothing while the keyboard is up', () {
      expect(dockInset(336, 34), 0);
      expect(dockInset(1, 34), 0);
    });

    test('carries the home-indicator inset while the keyboard is down', () {
      expect(dockInset(0, 34), 34);
    });

    test('falls back to a minimum on a device with no home indicator', () {
      expect(dockInset(0, 0), kMinDockInset);
    });
  });
}
