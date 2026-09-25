String commandRefusalMessage(String command, String? code) => switch (code) {
  'SESSION_BUSY' => 'The agent is busy — try again in a moment',
  'SESSION_COMMAND_UNAVAILABLE' => command == 'stop' ? 'The agent is idle' : 'The agent is working',
  'SESSION_AWAITING_DECISION' => 'Answer the permission request first',
  'SESSION_COMPOSER_NOT_EMPTY' => 'Clear the draft in the terminal first',
  'SESSION_NOT_RUNNING' => "The agent isn't running",
  'SESSION_NOT_FOUND' => 'Session not found',
  _ => switch (command) {
    'stop' => "Couldn't stop the agent",
    'compact' => "Couldn't compact",
    'model' => "Couldn't switch the model",
    _ => "Couldn't run $command",
  },
};
