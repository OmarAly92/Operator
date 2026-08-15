const String kActiveStorageKey = 'opr.telemetry.activeDay';

abstract class ActiveStorage {
  Future<String?> getItem(String key);

  Future<void> setItem(String key, String value);
}

Future<bool> reserveDailyActive(ActiveStorage? storage, DateTime now) async {
  if (storage == null) return true;
  final today = now.toUtc().toIso8601String().substring(0, 10);
  try {
    final stored = await storage.getItem(kActiveStorageKey);
    if (stored == today) return false;
    await storage.setItem(kActiveStorageKey, today);
    return true;
  } catch (_) {
    return true;
  }
}
