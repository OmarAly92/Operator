import 'package:operator_mobile/core/error_handling/failures/failure.dart';

/// The daemon's code for "paused on a permission decision". `POST
/// /sessions/{id}/send` refuses with it and advises answering in the terminal,
/// so that one code — and only that one — reroutes the send to the PTY.
const String kAwaitingDecision = 'SESSION_AWAITING_DECISION';

enum SendTarget { agent, terminal }

bool shouldRetryOnTerminal(Failure? failure) => failure?.apiStatus == kAwaitingDecision;

SendTarget routeForSend(SendTarget target, [Failure? failure]) {
  if (target == SendTarget.terminal) return SendTarget.terminal;
  return shouldRetryOnTerminal(failure) ? SendTarget.terminal : SendTarget.agent;
}

/// The trailing carriage return is the Enter the user would otherwise have to
/// press. Interior newlines collapse to spaces first: a PTY reads every one of
/// them as its own Enter, so one message must submit exactly once.
String terminalPayload(String text) =>
    '${text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim()}\r';

const String kReroutedNotice = 'Agent was paused on a prompt — sent straight to the terminal.';
const String kTerminalModeNotice = 'Sending composer text straight to the terminal.';
const String kTerminalUnavailableNotice = 'Terminal is not connected yet — text was not sent.';
