import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

void main() {
  group('launchDestination', () {
    test('a fresh install onboards', () {
      expect(launchDestination(desktopCount: 0, hasActive: false), LaunchDestination.onboarding);
    });

    test('an active desktop goes straight to sessions', () {
      expect(launchDestination(desktopCount: 2, hasActive: true), LaunchDestination.sessions);
    });

    test('saved desktops with none active show the list', () {
      expect(launchDestination(desktopCount: 1, hasActive: false), LaunchDestination.desktops);
    });

    test('an active flag without rows is treated as no desktops', () {
      expect(launchDestination(desktopCount: 0, hasActive: true), LaunchDestination.onboarding);
    });
  });
}
