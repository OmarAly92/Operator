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

  static String notification(String id) => '$notifications/${Uri.encodeComponent(id)}';
  static String pushDevice(String token) => '$pushDevices/${Uri.encodeComponent(token)}';

  static String sessionPr(String sessionId) => '/api/v1/sessions/$sessionId/pr';
  static String sessionKill(String sessionId) => '/api/v1/sessions/$sessionId/kill';
  static String sessionRestore(String sessionId) => '/api/v1/sessions/$sessionId/restore';
  static String prMerge(int number) => '/api/v1/prs/$number/merge';
  static String sessionConversation(String sessionId) => '${_session(sessionId)}/conversation';
  static String conversationMessages(String sessionId) => '${sessionConversation(sessionId)}/messages';
  static String conversationSteer(String sessionId) => '${sessionConversation(sessionId)}/steer';
  static String conversationInterrupt(String sessionId) => '${sessionConversation(sessionId)}/interrupt';
  static String conversationCompact(String sessionId) => '${sessionConversation(sessionId)}/compact';
  static String conversationModels(String sessionId) => '${sessionConversation(sessionId)}/models';
  static String conversationSkills(String sessionId) => '${sessionConversation(sessionId)}/skills';
  static String conversationSettings(String sessionId) => '${sessionConversation(sessionId)}/settings';
  static String conversationTitle(String sessionId) => '${sessionConversation(sessionId)}/title';
  static String conversationMcpReload(String sessionId) => '${sessionConversation(sessionId)}/mcp/reload';
  static String conversationConfigOptions(String sessionId) =>
      '${sessionConversation(sessionId)}/config-options';
  static String conversationConfigOption(String sessionId, String optionId) =>
      '${sessionConversation(sessionId)}/config-options/${Uri.encodeComponent(optionId)}';
  static String conversationApprovalResolve(String sessionId, String requestId) =>
      '${sessionConversation(sessionId)}/approvals/${Uri.encodeComponent(requestId)}/resolve';
  static String conversationInputResolve(String sessionId, String requestId) =>
      '${sessionConversation(sessionId)}/inputs/${Uri.encodeComponent(requestId)}/resolve';
  static String conversationTurnRollback(String sessionId, String turnId) =>
      '${sessionConversation(sessionId)}/turns/${Uri.encodeComponent(turnId)}/rollback';
  static String sessionAttachments(String sessionId) => '${_session(sessionId)}/attachments';
  static String sessionWorkspaceFiles(String sessionId) => '${_session(sessionId)}/workspace/files';
  static String sessionResumeAgent(String sessionId) => '${_session(sessionId)}/resume-agent';

  static const String shellTerminals = '/api/v1/shell-terminals';

  static String shellTerminal(String handleId) =>
      '$shellTerminals/${Uri.encodeComponent(handleId)}';
  static String sessionSend(String sessionId) => '${_session(sessionId)}/send';
  static String sessionInterfaceTransition(String sessionId) =>
      '${_session(sessionId)}/interface-transition';

  static String _session(String sessionId) => '$sessions/${Uri.encodeComponent(sessionId)}';
}
