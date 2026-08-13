sealed class EndPoints {
  static const String health = '/healthz';
  static const String projects = '/api/v1/projects';
  static const String sessions = '/api/v1/sessions';
  static const String orchestrators = '/api/v1/orchestrators';
  static const String settings = '/api/v1/settings';
  static const String agents = '/api/v1/agents';
  static const String agentsRefresh = '/api/v1/agents/refresh';
  static const String notifications = '/api/v1/notifications';

  static String sessionPr(String sessionId) => '/api/v1/sessions/$sessionId/pr';
  static String sessionKill(String sessionId) => '/api/v1/sessions/$sessionId/kill';
  static String sessionRestore(String sessionId) => '/api/v1/sessions/$sessionId/restore';
  static String prMerge(int number) => '/api/v1/prs/$number/merge';
}
