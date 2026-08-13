import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

void main() {
  Failure failure({String? code, String message = 'nope'}) =>
      ServerFailure(error: message, message: message, apiStatus: code, statusCode: 409);

  group('isChatPreflightFailure', () {
    test('recognises every code that means chat cannot start', () {
      for (final code in [
        'SESSION_MODE_UNSUPPORTED',
        'CHAT_DRIVER_UNAVAILABLE',
        'CHAT_DRIVER_INCOMPATIBLE',
        'CHAT_AUTH_REQUIRED',
      ]) {
        expect(isChatPreflightFailure(failure(code: code)), isTrue, reason: code);
      }
    });

    test('is false for any other failure', () {
      expect(isChatPreflightFailure(failure(code: 'SESSION_AWAITING_DECISION')), isFalse);
      expect(isChatPreflightFailure(failure()), isFalse);
    });
  });

  group('chatErrorCopy', () {
    test('keeps the daemon detail as-is when there is no envelope prefix', () {
      expect(chatErrorCopy(failure(message: 'claude-code cannot run Chat')), 'claude-code cannot run Chat');
    });

    test('strips an HTTP envelope prefix', () {
      expect(chatErrorCopy(failure(message: '409 Conflict - claude-code cannot run Chat')),
          'claude-code cannot run Chat');
    });

    test('never returns blank', () {
      expect(chatErrorCopy(failure(message: '')).isNotEmpty, isTrue);
    });
  });
}
