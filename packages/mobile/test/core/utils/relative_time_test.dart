import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';

void main() {
  final now = DateTime.parse('2026-07-30T12:00:00Z');
  String ago(Duration d) => now.subtract(d).toIso8601String();

  group('relativeTime', () {
    test('collapses anything under a minute to now', () {
      expect(relativeTime(ago(const Duration(seconds: 5)), now: now), 'now');
    });

    test('steps through minutes, hours, days and weeks', () {
      expect(relativeTime(ago(const Duration(minutes: 3)), now: now), '3m');
      expect(relativeTime(ago(const Duration(hours: 4)), now: now), '4h');
      expect(relativeTime(ago(const Duration(days: 2)), now: now), '2d');
      expect(relativeTime(ago(const Duration(days: 20)), now: now), '2w');
    });

    test('clamps a future timestamp to now rather than going negative', () {
      expect(relativeTime(ago(const Duration(seconds: -30)), now: now), 'now');
    });

    test('returns empty for an unparseable or missing timestamp', () {
      expect(relativeTime('not-a-date', now: now), '');
      expect(relativeTime(null, now: now), '');
    });
  });
}
