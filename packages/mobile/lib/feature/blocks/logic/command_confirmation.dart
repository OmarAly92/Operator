import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';

/// The daemon reports only that a write landed and the screen moved; whether a
/// command took effect is read from the streams this client already receives.
/// A command whose signal never arrives is shown as unconfirmed, never as done.
enum CommandPhase { idle, sending, sent, confirmed, unconfirmed }

const kCommandConfirmationBudget = Duration(seconds: 20);

bool confirmsCommand(String command, BlockEventModel event) {
  switch (command) {
    case 'compact':
      return event.kind == 'compaction';
    case 'model':
      return event.kind == 'turn_model';
    default:
      return false;
  }
}

/// Stop is confirmed by the session leaving the active state. The stop hook
/// arrives as an activity patch rather than a block, so it is checked apart
/// from confirmsCommand.
bool confirmsStop(String? activity) => activity == 'idle';
