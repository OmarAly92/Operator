part of 'cache_helper.dart';

sealed class CacheKeys {
  static const String currentTheme = 'current-theme';
  static const String serverHost = 'server.host';
  static const String serverHttpPort = 'server.httpPort';
  static const String serverSecure = 'server.secure';
  static const String serverPassword = 'server.password';
  static const String onboardingSkipped = 'opr.onboardingSkipped';
  static const String activeProjectId = 'opr.activeProjectId';
  static String chatDraft(String sessionId) => 'opr.chat.draft.$sessionId';
  static String chatEventCursor(String host, String port, String sessionId) =>
      'opr.chat.events.$host.$port.$sessionId';
  static const String telemetryRateLimit = 'opr.telemetry.rateLimit';
}
