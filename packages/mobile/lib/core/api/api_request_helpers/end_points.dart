sealed class EndPoints {
  static const String health = '/healthz';
  static const String projects = '/api/v1/projects';
  static const String sessions = '/api/v1/sessions';
  static const String settings = '/api/v1/settings';
  static const String agents = '/api/v1/agents';
  static const String notifications = '/api/v1/notifications';

  static String sessionPr(String sessionId) => '/api/v1/sessions/$sessionId/pr';
}
