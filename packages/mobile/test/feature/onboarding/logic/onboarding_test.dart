import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

void main() {
  group('shouldOnboard', () {
    test('onboards a fresh install', () {
      expect(shouldOnboard(configured: false, skipped: false), isTrue);
    });

    test('does not onboard once a server is configured', () {
      expect(shouldOnboard(configured: true, skipped: false), isFalse);
    });

    test('does not onboard after the user skipped', () {
      expect(shouldOnboard(configured: false, skipped: true), isFalse);
    });

    test('does not onboard when configured and skipped', () {
      expect(shouldOnboard(configured: true, skipped: true), isFalse);
    });

    test('waits while the config is still loading', () {
      expect(shouldOnboard(configured: null, skipped: false), isFalse);
    });

    test('waits while the skip flag is still loading', () {
      expect(shouldOnboard(configured: false, skipped: null), isFalse);
    });

    test('waits while both are still loading', () {
      expect(shouldOnboard(configured: null, skipped: null), isFalse);
    });
  });
}
