const String kPermissionModeEventKind = 'permission_mode';

const List<String> kPermissionModes = ['bypass-permissions', 'auto', 'accept-edits', 'plan', 'default'];

const String kPermissionRestartNote = 'Restarts the agent; the conversation continues';

String permissionModeLabel(String? mode) => switch (mode) {
  'bypass-permissions' => 'Bypass permissions',
  'auto' => 'Auto',
  'accept-edits' => 'Accept edits',
  'plan' => 'Plan',
  'default' => 'Ask',
  _ => 'Unknown',
};

String permissionModeRefusal(String? code) => switch (code) {
  'SESSION_BUSY' || 'SESSION_COMMAND_UNAVAILABLE' => 'The agent is working — try again when it is idle',
  'SESSION_AWAITING_DECISION' => 'Answer the permission request first',
  'PERMISSION_MODE_UNSUPPORTED' => "This agent can't change mode from the phone",
  'PERMISSION_MODE_UNCONFIRMED' => "The terminal didn't confirm the new mode",
  'SESSION_NOT_RUNNING' => "The agent isn't running",
  'SESSION_NOT_FOUND' => 'Session not found',
  _ => "Couldn't change the permission mode",
};
