const Set<String> _activePhases = {
  'requested',
  'preflighting',
  'draining',
  'source_stopping',
  'source_stopped',
  'target_starting',
  'activating',
};

const Set<String> _cancellablePhases = {'requested', 'preflighting', 'draining'};

bool interfaceTransitionIsActive(String? phase) => phase != null && _activePhases.contains(phase);

bool interfaceTransitionIsCancellable(String? phase) =>
    phase != null && _cancellablePhases.contains(phase);

String interfaceTransitionLabel(String? phase) => switch (phase) {
  'draining' =>
    'Waiting for the current terminal turn to finish. New Operator messages are queued safely.',
  'source_stopping' => 'Stopping the terminal controller before Chat starts.',
  'source_stopped' =>
    'Terminal controller stopped. The worktree and native conversation are unchanged.',
  'target_starting' => 'Resuming the same native conversation in Chat.',
  'activating' => 'Opening the Chat interface.',
  _ => 'Checking that Chat can resume this agent\'s native conversation.',
};
