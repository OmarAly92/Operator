sealed class PreferenceKeys {
  static const String themeMode = 'theme.mode';
  static const String telemetryRateLimit = 'telemetry.rateLimit';

  static String activeProject(String desktopId) => 'board.activeProject.$desktopId';

  static String sessionView(String key) => 'session.view.$key';
}
