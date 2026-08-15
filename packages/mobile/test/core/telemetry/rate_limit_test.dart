import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';

final int t0 = DateTime.utc(2026, 8, 7, 10).millisecondsSinceEpoch;

const String feature = 'opr.v2.mobile_app.feature_used';

({RateLimitState state, List<bool> results}) run(int count, {RateLimitState start = const {}}) {
  var state = start;
  final results = <bool>[];
  for (var i = 0; i < count; i++) {
    final decision = checkRateLimit(state, feature, t0);
    state = decision.state;
    results.add(decision.allowed);
  }
  return (state: state, results: results);
}

NameWindow window({int minuteStart = 0, int minuteCount = 0, String day = '2026-08-07', int dayCount = 0}) =>
    NameWindow(minuteStart: minuteStart, minuteCount: minuteCount, day: day, dayCount: dayCount);

void main() {
  test('allows up to the per-minute cap, then denies within the same minute', () {
    final outcome = run(kEventsPerNamePerMinute + 3);

    expect(outcome.results.take(kEventsPerNamePerMinute), everyElement(isTrue));
    expect(outcome.results.skip(kEventsPerNamePerMinute), everyElement(isFalse));
  });

  test('reopens the minute window after 60s', () {
    final outcome = run(kEventsPerNamePerMinute);

    expect(checkRateLimit(outcome.state, feature, t0 + 61000).allowed, isTrue);
  });

  test('enforces the daily ceiling across many minute windows', () {
    var state = <String, NameWindow>{};
    var allowed = 0;
    for (var i = 0; i < kEventsPerNamePerDay + 50; i++) {
      final decision = checkRateLimit(state, 'opr.v2.mobile_app.connected', t0 + i * 30000);
      state = decision.state;
      if (decision.allowed) allowed++;
    }

    expect(allowed, kEventsPerNamePerDay);
  });

  test('resets the daily counter on a new UTC day', () {
    var state = <String, NameWindow>{};
    for (var i = 0; i < kEventsPerNamePerDay; i++) {
      state = checkRateLimit(state, 'opr.v2.app.active', t0 + i * 1000).state;
    }

    final capped = checkRateLimit(state, 'opr.v2.app.active', t0 + 5000);
    expect(capped.allowed, isFalse);

    final nextDay = checkRateLimit(
      capped.state,
      'opr.v2.app.active',
      DateTime.utc(2026, 8, 8, 0, 1).millisecondsSinceEpoch,
    );
    expect(nextDay.allowed, isTrue);
  });

  test('caps each event name independently', () {
    var state = <String, NameWindow>{};
    for (var i = 0; i < kEventsPerNamePerMinute; i++) {
      state = checkRateLimit(state, 'a', t0).state;
    }

    expect(checkRateLimit(state, 'a', t0).allowed, isFalse);
    expect(checkRateLimit(state, 'b', t0).allowed, isTrue);
  });

  test('keeps the higher day count for the same day, so a restart cannot reset it', () {
    final merged = mergeRateState(
      {feature: window(dayCount: 199)},
      {feature: window(minuteStart: 1, minuteCount: 1, dayCount: 1)},
    );

    expect(merged[feature]!.dayCount, 199);
  });

  test('drops a persisted entry from an older day', () {
    final merged = mergeRateState(
      {'x': window(day: '2026-08-06', dayCount: 200)},
      {'x': window(minuteCount: 1, dayCount: 1)},
    );

    expect(merged['x']!.dayCount, 1);
  });

  test('carries a persisted name the current session has not touched, and survives a round trip', () {
    final merged = mergeRateState({'y': window(dayCount: 42)}, const {});

    expect(merged['y']!.dayCount, 42);
    expect(NameWindow.fromJson(merged['y']!.toJson()), merged['y']);
  });
}
