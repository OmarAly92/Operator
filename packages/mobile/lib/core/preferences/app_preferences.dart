import 'package:flutter/material.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';

sealed class AppPreferences {
  static final Map<String, String> _values = {};
  static SettingsDao? _dao;
  static Future<void> _writes = Future<void>.value();

  static Future<void> load(SettingsDao dao) async {
    _dao = dao;
    _values.clear();
    try {
      _values.addAll(await dao.readAll());
    } on Failure {
      return;
    }
  }

  @visibleForTesting
  static void debugLoad(Map<String, String> values, {SettingsDao? dao}) {
    _dao = dao;
    _writes = Future<void>.value();
    _values
      ..clear()
      ..addAll(values);
  }

  static Future<void> flush() => _writes;

  static ThemeMode? get themeMode {
    final saved = _values[PreferenceKeys.themeMode];
    for (final mode in ThemeMode.values) {
      if (mode.name == saved) return mode;
    }
    return null;
  }

  static void setThemeMode(ThemeMode mode) => _write(PreferenceKeys.themeMode, mode.name);

  static String? activeProjectId(String desktopId) => _values[PreferenceKeys.activeProject(desktopId)];

  static void setActiveProjectId(String desktopId, String projectId) =>
      _write(PreferenceKeys.activeProject(desktopId), projectId);

  static String? sessionView(String key) => _values[PreferenceKeys.sessionView(key)];

  static void setSessionView(String key, String mode) => _write(PreferenceKeys.sessionView(key), mode);

  static String? get telemetryRateLimit => _values[PreferenceKeys.telemetryRateLimit];

  static void setTelemetryRateLimit(String value) => _write(PreferenceKeys.telemetryRateLimit, value);

  static String? string(String key) => _values[key];

  static Future<void> setString(String key, String value) {
    _write(key, value);
    return _writes;
  }

  static void _write(String key, String value) {
    _values[key] = value;
    final dao = _dao;
    if (dao == null) return;
    _writes = _writes.then((_) => dao.put(key, value)).catchError((Object _) {});
  }
}
