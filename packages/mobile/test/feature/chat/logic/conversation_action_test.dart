import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';

Failure failure(String? code, [String message = 'conflict']) => ServerFailure(
  error: message,
  message: message,
  statusCode: 409,
  apiStatus: code,
);

void main() {
  group('mobile conversation action errors', () {
    test('turns protocol codes into instructions the user can act on', () {
      expect(
        conversationActionError(failure('CHAT_NO_ACTIVE_TURN')),
        contains('Queue it as a new message'),
      );
      expect(
        conversationActionError(failure('CHAT_COMPACTION_BUSY')),
        'Stop the current turn before compacting history.',
      );
      expect(
        conversationActionError(failure('CHAT_MCP_RELOAD_UNSUPPORTED')),
        'This agent cannot reload its MCP servers.',
      );
      expect(
        conversationActionError(failure('CHAT_STEER_UNSUPPORTED')),
        contains('Queue a new message'),
      );
      expect(
        conversationActionError(failure('CHAT_TURN_RUNNING')),
        contains('Stop the current turn'),
      );
      expect(
        conversationActionError(failure('CHAT_REQUEST_NOT_PENDING')),
        contains('already answered'),
      );
    });

    test('keeps the daemon detail for codes that carry their own message', () {
      expect(
        conversationActionError(
          failure('CHAT_TURN_NOT_STEERABLE', 'The turn is draining.'),
        ),
        startsWith('The turn is draining.'),
      );
      expect(
        conversationActionError(
          failure('CHAT_PROVIDER_REFUSED', 'The provider said no.'),
        ),
        'The provider said no.',
      );
      expect(
        conversationActionError(
          failure(null, 'Could not reach your Operator server'),
        ),
        'Could not reach your Operator server',
      );
    });

    test(
      'preserves typed refusal identities so unsupported controls can withdraw',
      () {
        final error = failure('CHAT_STEER_UNSUPPORTED');
        expect(conversationErrorCode(error), 'CHAT_STEER_UNSUPPORTED');
        expect(
          conversationActionUnsupported('steer', conversationErrorCode(error)),
          isTrue,
        );
        expect(
          conversationActionUnsupported(
            'compact',
            conversationErrorCode(error),
          ),
          isFalse,
        );
      },
    );

    test(
      'names the codes that make a conversation permanently unavailable',
      () {
        expect(kPermanentConversationCodes, contains('SESSION_MODE_MISMATCH'));
        expect(kPermanentConversationCodes, contains('CHAT_RESUME_FAILED'));
        expect(
          kPermanentConversationCodes,
          isNot(contains('CHAT_COMPACTION_BUSY')),
        );
      },
    );
  });
}
