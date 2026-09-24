import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';

void main() {
  test('under a minute prints seconds', () {
    expect(turnElapsed(Duration.zero), '0s');
    expect(turnElapsed(const Duration(seconds: 12)), '12s');
    expect(turnElapsed(const Duration(seconds: 59)), '59s');
  });

  test('under an hour prints minutes and seconds', () {
    expect(turnElapsed(const Duration(seconds: 60)), '1m0s');
    expect(turnElapsed(const Duration(minutes: 2, seconds: 5)), '2m5s');
    expect(turnElapsed(const Duration(minutes: 59, seconds: 59)), '59m59s');
  });

  test('an hour or more prints hours and minutes, no seconds', () {
    expect(turnElapsed(const Duration(hours: 1)), '1h 0m');
    expect(turnElapsed(const Duration(hours: 3, minutes: 30, seconds: 59)), '3h 30m');
    expect(turnElapsed(const Duration(minutes: 210, seconds: 59)), '3h 30m');
    expect(turnElapsed(const Duration(hours: 26, minutes: 4)), '26h 4m');
  });

  test('spaced separates minutes and seconds only', () {
    expect(turnElapsed(const Duration(seconds: 12), spaced: true), '12s');
    expect(turnElapsed(const Duration(minutes: 6, seconds: 56), spaced: true), '6m 56s');
    expect(turnElapsed(const Duration(hours: 3, minutes: 30), spaced: true), '3h 30m');
  });

  test('a negative duration clamps to zero', () {
    expect(turnElapsed(const Duration(seconds: -5)), '0s');
  });
}
