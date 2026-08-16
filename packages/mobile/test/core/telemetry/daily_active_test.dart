import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';

class _MemoryStorage implements ActiveStorage {
  _MemoryStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> getItem(String key) async => values[key];

  @override
  Future<void> setItem(String key, String value) async => values[key] = value;
}

class _ThrowingStorage implements ActiveStorage {
  @override
  Future<String?> getItem(String key) async => throw StateError('keystore locked');

  @override
  Future<void> setItem(String key, String value) async => throw StateError('keystore locked');
}

void main() {
  test('returns true once per UTC day and false for the rest of that day', () async {
    final storage = _MemoryStorage();

    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 0, 5)), isTrue);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 9)), isFalse);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 23, 59, 59)), isFalse);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 7)), isTrue);
  });

  test('persists the reserved day', () async {
    final storage = _MemoryStorage();

    await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 10));

    expect(storage.values[kActiveStorageKey], '2026-08-06');
  });

  test('reads a day already reported by a previous launch as spent', () async {
    final storage = _MemoryStorage({kActiveStorageKey: '2026-08-06'});

    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 14)), isFalse);
  });

  test('allows the emit when storage is unavailable', () async {
    expect(await reserveDailyActive(null, DateTime.utc(2026, 8, 6, 10)), isTrue);
  });

  test('allows the emit when storage throws rather than losing the user', () async {
    expect(await reserveDailyActive(_ThrowingStorage(), DateTime.utc(2026, 8, 6, 10)), isTrue);
  });
}
