import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

void main() {
  group('shouldOnboard', () {
    test('onboards a fresh install', () {
      expect(shouldOnboard(configured: false), isTrue);
    });

    test('does not onboard once a server is configured', () {
      expect(shouldOnboard(configured: true), isFalse);
    });

    test('waits while the config is still loading', () {
      expect(shouldOnboard(configured: null), isFalse);
    });
  });
}
