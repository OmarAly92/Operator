part of 'cache_helper.dart';

sealed class CacheKeys {
  static const String currentTheme = 'current-theme';
  static const String activeProjectId = 'opr.activeProjectId';
  static String chatDraft(String sessionId) => 'opr.chat.draft.$sessionId';
  static String sessionView(String key) => 'opr.session.view.$key';
  static const String telemetryRateLimit = 'opr.telemetry.rateLimit';
}
