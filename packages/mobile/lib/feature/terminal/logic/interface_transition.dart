const Set<String> _activePhases = {
  'requested',
  'preflighting',
  'draining',
  'source_stopping',
  'source_stopped',
  'target_starting',
  'activating',
};

const Set<String> _cancellablePhases = {
  'requested',
  'preflighting',
  'draining',
};

bool interfaceTransitionIsActive(String? phase) =>
    phase != null && _activePhases.contains(phase);

bool interfaceTransitionIsCancellable(String? phase) =>
    phase != null && _cancellablePhases.contains(phase);

String interfaceTransitionLabel(
  String? phase, {
  String sourceLabel = 'terminal',
  String targetLabel = 'Chat',
}) {
  final sourceCapitalized = sourceLabel.isEmpty
      ? sourceLabel
      : sourceLabel[0].toUpperCase() + sourceLabel.substring(1);
  return switch (phase) {
    'draining' =>
      'Waiting for the current $sourceLabel turn to finish. New Operator messages are queued safely.',
    'source_stopping' =>
      'Stopping the $sourceLabel controller before $targetLabel starts.',
    'source_stopped' =>
      '$sourceCapitalized controller stopped. The worktree and native conversation are unchanged.',
    'target_starting' =>
      'Resuming the same native conversation in $targetLabel.',
    'activating' => 'Opening the $targetLabel interface.',
    _ =>
      'Checking that $targetLabel can resume this agent\'s native conversation.',
  };
}
