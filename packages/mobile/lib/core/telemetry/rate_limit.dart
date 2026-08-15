import 'package:equatable/equatable.dart';

const int kEventsPerNamePerMinute = 5;
const int kEventsPerNamePerDay = 200;

typedef RateLimitState = Map<String, NameWindow>;

class NameWindow extends Equatable {
  const NameWindow({
    required this.minuteStart,
    required this.minuteCount,
    required this.day,
    required this.dayCount,
  });

  final int minuteStart;
  final int minuteCount;
  final String day;
  final int dayCount;

  factory NameWindow.fromJson(Map<String, dynamic> json) => NameWindow(
    minuteStart: (json['minuteStart'] as num?)?.toInt() ?? 0,
    minuteCount: (json['minuteCount'] as num?)?.toInt() ?? 0,
    day: json['day'] as String? ?? '',
    dayCount: (json['dayCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'minuteStart': minuteStart,
    'minuteCount': minuteCount,
    'day': day,
    'dayCount': dayCount,
  };

  @override
  List<Object?> get props => [minuteStart, minuteCount, day, dayCount];
}

class RateLimitDecision extends Equatable {
  const RateLimitDecision({required this.allowed, required this.state});

  final bool allowed;
  final RateLimitState state;

  @override
  List<Object?> get props => [allowed, state];
}

String _utcDay(int nowMs) =>
    DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).toIso8601String().substring(0, 10);

RateLimitDecision checkRateLimit(
  RateLimitState state,
  String name,
  int nowMs, {
  int perMinute = kEventsPerNamePerMinute,
  int perDay = kEventsPerNamePerDay,
}) {
  final previous = state[name];
  final day = _utcDay(nowMs);
  final minuteStart = previous != null && nowMs - previous.minuteStart < 60000
      ? previous.minuteStart
      : nowMs;
  final minuteCount = previous != null && previous.minuteStart == minuteStart
      ? previous.minuteCount
      : 0;
  final dayCount = previous != null && previous.day == day ? previous.dayCount : 0;
  final allowed = minuteCount < perMinute && dayCount < perDay;

  return RateLimitDecision(
    allowed: allowed,
    state: {
      ...state,
      name: NameWindow(
        minuteStart: minuteStart,
        minuteCount: allowed ? minuteCount + 1 : minuteCount,
        day: day,
        dayCount: allowed ? dayCount + 1 : dayCount,
      ),
    },
  );
}

RateLimitState mergeRateState(RateLimitState persisted, RateLimitState current) {
  final merged = {...persisted};
  for (final entry in current.entries) {
    final previous = merged[entry.key];
    if (previous == null || previous.day != entry.value.day) {
      merged[entry.key] = entry.value;
      continue;
    }
    merged[entry.key] = NameWindow(
      day: entry.value.day,
      dayCount: previous.dayCount > entry.value.dayCount ? previous.dayCount : entry.value.dayCount,
      minuteStart: previous.minuteStart > entry.value.minuteStart
          ? previous.minuteStart
          : entry.value.minuteStart,
      minuteCount: previous.minuteCount > entry.value.minuteCount
          ? previous.minuteCount
          : entry.value.minuteCount,
    );
  }
  return merged;
}
