import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/command_refusal.dart';

void main() {
  test('a busy session reads as busy for every command', () {
    for (final command in ['stop', 'compact', 'model']) {
      expect(commandRefusalMessage(command, 'SESSION_BUSY'), 'The agent is busy — try again in a moment');
    }
  });

  test('an unavailable command names the activity it needs', () {
    expect(commandRefusalMessage('stop', 'SESSION_COMMAND_UNAVAILABLE'), 'The agent is idle');
    expect(commandRefusalMessage('compact', 'SESSION_COMMAND_UNAVAILABLE'), 'The agent is working');
  });

  test('the other daemon refusals get their own copy', () {
    expect(commandRefusalMessage('stop', 'SESSION_AWAITING_DECISION'), 'Answer the permission request first');
    expect(commandRefusalMessage('stop', 'SESSION_COMPOSER_NOT_EMPTY'), 'Clear the draft in the terminal first');
    expect(commandRefusalMessage('stop', 'SESSION_NOT_RUNNING'), "The agent isn't running");
    expect(commandRefusalMessage('stop', 'SESSION_NOT_FOUND'), 'Session not found');
  });

  test('an unknown or missing code falls back to naming the command', () {
    expect(commandRefusalMessage('stop', null), "Couldn't stop the agent");
    expect(commandRefusalMessage('model', 'X'), "Couldn't switch the model");
  });
}
