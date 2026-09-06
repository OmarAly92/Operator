sealed class EndPoints {
  static const String health = '/healthz';
  static const String projects = '/api/v1/projects';
  static const String sessions = '/api/v1/sessions';
  static const String orchestrators = '/api/v1/orchestrators';
  static const String settings = '/api/v1/settings';
  static const String agents = '/api/v1/agents';
  static const String agentsRefresh = '/api/v1/agents/refresh';
  static const String notifications = '/api/v1/notifications';
  static const String notificationsReadAll = '/api/v1/notifications/read-all';
  static const String pushDevices = '/api/v1/push/devices';
  static const String events = '/api/v1/events';
  static const String usageRollup = '/api/v1/usage/rollup';
  static const String usageQuota = '/api/v1/usage/quota';

  static String notification(String id) => '$notifications/${Uri.encodeComponent(id)}';
  static String pushDevice(String token) => '$pushDevices/${Uri.encodeComponent(token)}';
  static String usageSession(String sessionId) =>
      '/api/v1/usage/sessions/${Uri.encodeComponent(sessionId)}';

  static String sessionPr(String sessionId) => '/api/v1/sessions/$sessionId/pr';
  static String sessionKill(String sessionId) => '/api/v1/sessions/$sessionId/kill';
  static String sessionRestore(String sessionId) => '/api/v1/sessions/$sessionId/restore';
  static String prMerge(int number) => '/api/v1/prs/$number/merge';
  static String sessionAttachments(String sessionId) => '${_session(sessionId)}/attachments';
  static String sessionWorkspaceFiles(String sessionId) => '${_session(sessionId)}/workspace/files';
  static String sessionResumeAgent(String sessionId) => '${_session(sessionId)}/resume-agent';

  static const String shellTerminals = '/api/v1/shell-terminals';

  static String shellTerminal(String handleId) =>
      '$shellTerminals/${Uri.encodeComponent(handleId)}';
  static String sessionSend(String sessionId) => '${_session(sessionId)}/send';
  static String sessionCommand(String sessionId) => '${_session(sessionId)}/command';
  static String sessionDecision(String sessionId) => '${_session(sessionId)}/decision';
  static String sessionAnswer(String sessionId) => '${_session(sessionId)}/answer';
  static String sessionInteractions(String sessionId) => '${_session(sessionId)}/interactions';
  static String sessionDraft(String sessionId) => '${_session(sessionId)}/draft';
  static String sessionBlocks(String sessionId) => '${_session(sessionId)}/blocks';

  static String sessionPreview(String sessionId) => '${_session(sessionId)}/preview';

  static String sessionPreviewFile(String sessionId, String entry) =>
      '${sessionPreview(sessionId)}/files/'
      '${entry.split('/').map(Uri.encodeComponent).join('/')}';

  static String _session(String sessionId) => '$sessions/${Uri.encodeComponent(sessionId)}';
}
