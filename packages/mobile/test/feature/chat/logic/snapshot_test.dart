import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_pages.dart';

ConversationSnapshotModel page({
  int oldestSequence = 1,
  bool hasMoreBefore = false,
  List<ConversationItemModel> items = const [],
  List<ConversationTurnModel> turns = const [],
}) => ConversationSnapshotModel(
  conversationId: 'conv-1',
  sessionId: 'session-1',
  harness: 'codex',
  mode: 'chat',
  controllerState: 'ready',
  latestSequence: 3,
  oldestSequence: oldestSequence,
  hasMoreBefore: hasMoreBefore,
  items: items,
  turns: turns,
);

ConversationMessageModel message(
  String id,
  int sequence, {
  int revision = 1,
  String text = '',
}) => ConversationMessageModel(
  id: id,
  sequence: sequence,
  revision: revision,
  text: text,
);

void main() {
  group('mobile conversation pagination', () {
    test('keeps chronological order and the oldest page cursor', () {
      final merged = mergeConversationPages([
        page(
          oldestSequence: 3,
          hasMoreBefore: true,
          items: [message('m3', 3, text: 'new')],
        ),
        page(oldestSequence: 1, items: [message('m1', 1, text: 'old')]),
      ])!;

      expect(merged.items.map((item) => item.id), ['m1', 'm3']);
      expect(merged.oldestSequence, 1);
      expect(merged.hasMoreBefore, isFalse);
    });

    test('lets the live page replace an overlapping streaming revision', () {
      final historical = message('m2', 2, text: 'hel');
      final live = message('m2', 2, revision: 2, text: 'hello');
      final merged = mergeConversationPages([
        page(items: [live]),
        page(items: [historical]),
      ])!;

      expect(merged.items, [live]);
    });

    test(
      'keeps one row per turn, newest revision, ordered by request time',
      () {
        final merged = mergeConversationPages([
          page(
            turns: [
              const ConversationTurnModel(
                id: 't2',
                state: 'running',
                requestedAt: '2026-08-05T00:00:02Z',
              ),
              const ConversationTurnModel(
                id: 't1',
                state: 'completed',
                requestedAt: '2026-08-05T00:00:01Z',
              ),
            ],
          ),
          page(
            turns: [
              const ConversationTurnModel(
                id: 't1',
                state: 'running',
                requestedAt: '2026-08-05T00:00:01Z',
              ),
            ],
          ),
        ])!;

        expect(merged.turns.map((turn) => turn.id), ['t1', 't2']);
        expect(merged.turns.first.state, 'completed');
      },
    );

    test(
      'drops stale historical rows before a rollback projection is reloaded',
      () {
        final live = page(oldestSequence: 3, hasMoreBefore: true);
        final historical = page();

        expect(discardHistoricalPages([live, historical]), [live]);
        expect(discardHistoricalPages(const []), isEmpty);
      },
    );

    test('has nothing to merge before the first page lands', () {
      expect(mergeConversationPages(const []), isNull);
    });
  });
}
