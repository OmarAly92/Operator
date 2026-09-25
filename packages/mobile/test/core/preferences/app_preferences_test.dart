import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';

class _FlakyDao extends SettingsDao {
  _FlakyDao(super.db);

  int failures = 1;

  @override
  Future<void> put(String key, String value) {
    if (failures > 0) {
      failures--;
      return Future<void>.error(LocalFailure<void>(error: 'disk full'));
    }
    return super.put(key, value);
  }
}

class _UnreadableDao extends SettingsDao {
  _UnreadableDao(super.db);

  @override
  Future<Map<String, String>> readAll() => Future<Map<String, String>>.error(LocalFailure<void>(error: 'corrupt'));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  tearDown(() async {
    AppPreferences.debugLoad(const {});
    await db.close();
  });

  test('load reads every row, then answers synchronously', () async {
    await db.settingsDao.put(PreferenceKeys.themeMode, 'dark');
    await db.settingsDao.put(PreferenceKeys.sessionView('s-1'), 'raw');

    await AppPreferences.load(db.settingsDao);

    expect(AppPreferences.themeMode, ThemeMode.dark);
    expect(AppPreferences.sessionView('s-1'), 'raw');
  });

  test('each typed accessor writes under its own key', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setThemeMode(ThemeMode.system);
    AppPreferences.setActiveProjectId('d-1', 'p-1');
    AppPreferences.setSessionView('s-1', 'blocks');
    AppPreferences.setTelemetryRateLimit('{}');
    await AppPreferences.setString('opr.telemetry.day', '2026-09-25');
    await AppPreferences.flush();

    expect(await db.settingsDao.readAll(), {
      'theme.mode': 'system',
      'board.activeProject.d-1': 'p-1',
      'session.view.s-1': 'blocks',
      'telemetry.rateLimit': '{}',
      'opr.telemetry.day': '2026-09-25',
    });
    expect(AppPreferences.telemetryRateLimit, '{}');
    expect(AppPreferences.string('opr.telemetry.day'), '2026-09-25');
  });

  test('the active project is remembered per desktop', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setActiveProjectId('d-1', 'p-1');

    expect(AppPreferences.activeProjectId('d-1'), 'p-1');
    expect(AppPreferences.activeProjectId('d-2'), isNull);
  });

  test('an unknown theme value reads as unset', () {
    AppPreferences.debugLoad({PreferenceKeys.themeMode: 'sepia'});

    expect(AppPreferences.themeMode, isNull);
  });

  test('writes reach memory at once and drift in order, so a reload after flush sees the last value', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setThemeMode(ThemeMode.dark);
    AppPreferences.setThemeMode(ThemeMode.light);
    expect(AppPreferences.themeMode, ThemeMode.light);
    await AppPreferences.flush();

    AppPreferences.debugLoad(const {});
    await AppPreferences.load(db.settingsDao);
    expect(AppPreferences.themeMode, ThemeMode.light);
  });

  test('a failed write keeps the value in memory and does not block later writes', () async {
    final flaky = _FlakyDao(db);
    AppPreferences.debugLoad(const {}, dao: flaky);

    AppPreferences.setThemeMode(ThemeMode.dark);
    AppPreferences.setSessionView('s-1', 'raw');
    await AppPreferences.flush();

    expect(AppPreferences.themeMode, ThemeMode.dark);
    expect(await db.settingsDao.readAll(), {'session.view.s-1': 'raw'});
  });

  test('an unreadable store loads as empty instead of failing launch', () async {
    await AppPreferences.load(_UnreadableDao(db));

    expect(AppPreferences.themeMode, isNull);
  });
}
