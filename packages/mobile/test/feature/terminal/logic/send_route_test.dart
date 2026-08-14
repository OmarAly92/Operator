import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';

Failure _failure({int? statusCode, String? code}) =>
    ServerFailure(error: 'x', message: 'x', statusCode: statusCode, apiStatus: code);

void main() {
  group('shouldRetryOnTerminal', () {
    test('retries when the daemon says the session is paused on a decision', () {
      expect(shouldRetryOnTerminal(_failure(statusCode: 409, code: kAwaitingDecision)), isTrue);
    });

    // The whole safety argument for auto-routing rests on this list. A dead
    // session has no PTY, so a "successful" write would swallow the user's text
    // and hide the real error behind a fake success.
    test('does NOT retry when there is no live PTY to write to', () {
      for (final code in const [
        'SESSION_TERMINATED',
        'AGENT_EXITED',
        'SESSION_NOT_FOUND',
        'SESSION_NOT_RESTORABLE',
      ]) {
        expect(shouldRetryOnTerminal(_failure(statusCode: 409, code: code)), isFalse);
      }
    });

    test('does not retry on auth, rate limiting, or an unrecognised failure', () {
      expect(shouldRetryOnTerminal(_failure(statusCode: 401)), isFalse);
      expect(shouldRetryOnTerminal(_failure(statusCode: 429)), isFalse);
      expect(shouldRetryOnTerminal(_failure(statusCode: 500, code: 'INTERNAL')), isFalse);
      expect(shouldRetryOnTerminal(null), isFalse);
    });

    test('does not retry when the server was never reached', () {
      expect(shouldRetryOnTerminal(ServerFailure.noNetwork()), isFalse);
    });
  });

  group('routeForSend', () {
    test('sends to the agent by default', () {
      expect(routeForSend(SendTarget.agent), SendTarget.agent);
    });

    test('honours the explicit terminal target', () {
      expect(routeForSend(SendTarget.terminal), SendTarget.terminal);
      expect(
        routeForSend(SendTarget.terminal, _failure(statusCode: 500, code: 'INTERNAL')),
        SendTarget.terminal,
      );
    });

    test('auto-engages the terminal route for a blocked prompt', () {
      expect(
        routeForSend(SendTarget.agent, _failure(statusCode: 409, code: kAwaitingDecision)),
        SendTarget.terminal,
      );
    });

    test('keeps ordinary failures on the agent route', () {
      expect(routeForSend(SendTarget.agent, _failure(statusCode: 401)), SendTarget.agent);
      expect(
        routeForSend(SendTarget.agent, _failure(statusCode: 409, code: 'SESSION_TERMINATED')),
        SendTarget.agent,
      );
    });
  });

  group('terminalPayload', () {
    test('submits the line with a carriage return', () {
      expect(terminalPayload('y'), 'y\r');
    });

    test('leaves single-line text otherwise untouched', () {
      expect(terminalPayload("git commit -m 'x'"), "git commit -m 'x'\r");
    });

    // The composer is multiline, so pasted text can carry newlines. A PTY reads
    // each one as Enter, which would answer a dialog with the first fragment and
    // feed the rest to whatever opened next.
    test('collapses interior newlines so one message submits once', () {
      expect(terminalPayload('yes,\nuse the second option'), 'yes, use the second option\r');
      expect(terminalPayload('a\r\nb'), 'a b\r');
      expect(terminalPayload('a\n\n\nb'), 'a b\r');
    });

    test('drops surrounding whitespace so there is no empty second submission', () {
      expect(terminalPayload('approve\n'), 'approve\r');
      expect(terminalPayload('\n approve \n'), 'approve\r');
    });

    test('still submits when the text is only newlines', () {
      expect(terminalPayload('\n\n'), '\r');
    });
  });
}
