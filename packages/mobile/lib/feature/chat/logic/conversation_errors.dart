import 'package:operator_mobile/core/error_handling/failures/failure.dart';

const Set<String> kPermanentConversationCodes = {
  'SESSION_MODE_MISMATCH',
  'SESSION_NOT_FOUND',
  'SESSION_MODE_UNSUPPORTED',
  'CHAT_DRIVER_UNAVAILABLE',
  'CHAT_DRIVER_INCOMPATIBLE',
  'CHAT_AUTH_REQUIRED',
  'CHAT_RESUME_FAILED',
  'CHAT_CONTROLLER_NOT_READY',
};

const Map<String, String> _unsupportedCodes = {
  'steer': 'CHAT_STEER_UNSUPPORTED',
  'compact': 'CHAT_COMPACTION_UNSUPPORTED',
  'mcp': 'CHAT_MCP_RELOAD_UNSUPPORTED',
};

String? conversationErrorCode(Failure failure) {
  final code = failure.apiStatus?.trim();
  return code == null || code.isEmpty ? null : code;
}

String conversationActionError(Failure failure) {
  switch (conversationErrorCode(failure)) {
    case 'CHAT_NO_ACTIVE_TURN':
      return 'The turn finished before this guidance landed. Queue it as a new message instead.';
    case 'CHAT_STEER_UNSUPPORTED':
      return 'This agent cannot take guidance while it is working. Queue a new message instead.';
    case 'CHAT_STEER_TEXT_REQUIRED':
      return 'Enter guidance before steering the running turn.';
    case 'CHAT_TURN_NOT_STEERABLE':
      final detail = failure.message.trim();
      final head = detail.isEmpty
          ? 'This turn cannot be steered right now.'
          : detail;
      return '$head Try again when it finishes, or queue a new message.';
    case 'CHAT_COMPACTION_BUSY':
      return 'Stop the current turn before compacting history.';
    case 'CHAT_COMPACTION_UNSUPPORTED':
      return 'This agent cannot compact its history.';
    case 'CHAT_MCP_RELOAD_UNSUPPORTED':
      return 'This agent cannot reload its MCP servers.';
    case 'CHAT_TURN_RUNNING':
      return 'Stop the current turn before rolling back conversation history.';
    case 'CHAT_TURN_NOT_ROLLBACKABLE':
      return 'That turn never reached the agent, so there is nothing to roll back.';
    case 'CHAT_ROLLBACK_UNSUPPORTED':
      return 'This agent cannot roll back conversation history.';
    case 'CHAT_TURN_NOT_FOUND':
      return 'That turn is no longer in this conversation. Refresh and choose another turn.';
    case 'CHAT_REQUEST_NOT_PENDING':
      return 'This request was already answered or is no longer waiting. Refresh the conversation.';
    case 'CHAT_DECISION_NOT_OFFERED':
      return 'That choice is no longer available. Refresh the conversation and choose an offered answer.';
    case 'CHAT_CONFIG_OPTION_INVALID':
      return 'The provider no longer accepts that setting. Refresh its controls and choose again.';
    case 'CHAT_CONFIG_OPTION_VALUE_REQUIRED':
      return 'Choose a value for that provider setting.';
    case 'CHAT_APPROVAL_MODE_INVALID':
      return 'The provider does not accept that approval mode.';
    case 'CHAT_DECISION_REQUIRED':
      return 'Choose one of the provider\'s approval options.';
    case 'CHAT_INPUT_ACTION_INVALID':
      return 'That response is not available for this request.';
    case 'CHAT_INPUT_CONTENT_INVALID':
      return 'The provider rejected the submitted form. Check the fields and try again.';
    case 'CHAT_RENAME_UNSUPPORTED':
      return 'This agent does not support conversation titles.';
    case 'CHAT_TITLE_REQUIRED':
      return 'Enter a conversation title.';
    case 'CHAT_CONTROLLER_NOT_READY':
      return 'The agent controller is not running. Resume it before trying again.';
    case 'CHAT_AUTH_REQUIRED':
      return 'Sign in with the agent CLI on the Operator host, then resume this session.';
    case 'CHAT_DRIVER_UNAVAILABLE':
      return 'The agent CLI is unavailable on the Operator host. Install it or open the worktree shell.';
    case 'CHAT_DRIVER_INCOMPATIBLE':
      return 'The installed agent CLI is not compatible with Operator Chat. Update it, then resume this session.';
    case 'CHAT_RESUME_FAILED':
      return 'Operator could not resume this agent. The conversation and worktree are preserved.';
    case 'CHAT_PROVIDER_REFUSED':
      final refusal = failure.message.trim();
      return refusal.isEmpty ? 'The provider refused this action.' : refusal;
    default:
      final message = failure.message.trim();
      return message.isEmpty ? 'The conversation request failed.' : message;
  }
}

bool conversationActionUnsupported(String action, String? code) =>
    code != null && _unsupportedCodes[action] == code;
