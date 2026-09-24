import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/utils/streaming_haptics.dart';

void main() {
  group('StreamingHaptics', () {
    test('onStreamStart fires once', () {
      var fires = 0;
      var now = Duration.zero;
      final haptics = StreamingHaptics(fire: () => fires++, clock: () => now);

      haptics.onStreamStart();

      expect(fires, 1);
    });

    test('onTextGrew throttles to at most once per streamingHapticGap', () {
      var fires = 0;
      var now = Duration.zero;
      final haptics = StreamingHaptics(fire: () => fires++, clock: () => now);

      haptics.onTextGrew();
      expect(fires, 1);

      now += const Duration(milliseconds: 100);
      haptics.onTextGrew();
      expect(fires, 1);

      now += AppMotion.streamingHapticGap;
      haptics.onTextGrew();
      expect(fires, 2);
    });

    test('enabled is false under reduce motion', () {
      var fires = 0;
      var now = Duration.zero;
      final haptics = StreamingHaptics(fire: () => fires++, clock: () => now, reduceMotion: true);

      expect(haptics.enabled, isFalse);

      haptics.onStreamStart();
      now += AppMotion.streamingHapticGap;
      haptics.onTextGrew();

      expect(fires, 0);
    });

    test('enabled is true without reduce motion', () {
      final haptics = StreamingHaptics(fire: () {}, clock: () => Duration.zero);

      expect(haptics.enabled, isTrue);
    });
  });
}
