import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';

ConversationActivityModel activity(
  String kind,
  int sequence, {
  String? turnId = 't1',
  String status = 'completed',
  Map<String, dynamic>? detail,
  String? providerItemId,
}) => ConversationActivityModel(
  id: '$kind-$sequence',
  turnId: turnId,
  sequence: sequence,
  revision: 1,
  activityKind: kind,
  status: status,
  summary: kind,
  providerItemId: providerItemId,
  detail: detail == null ? null : ActivityDetailModel(detail),
);

ConversationSnapshotModel snapshot({
  List<ConversationTurnModel>? turns,
  List<ConversationItemModel>? items,
  List<String> capabilities = const ['rollback'],
}) => ConversationSnapshotModel(
  conversationId: 'c',
  sessionId: 's',
  harness: 'codex',
  mode: 'chat',
  controllerState: 'ready',
  latestSequence: 4,
  oldestSequence: 1,
  capabilities: capabilities,
  turns:
      turns ??
      const [
        ConversationTurnModel(
          id: 't1',
          state: 'completed',
          providerTurnId: 'p1',
          requestedAt: '2026-08-05T00:00:00Z',
        ),
        ConversationTurnModel(
          id: 't2',
          state: 'completed',
          providerTurnId: 'p2',
          requestedAt: '2026-08-05T00:00:01Z',
        ),
      ],
  items:
      items ??
      const [
        ConversationMessageModel(
          id: 'u1',
          turnId: 't1',
          sequence: 1,
          revision: 1,
          role: 'user',
          origin: 'human',
          text: 'First task',
        ),
        ConversationMessageModel(
          id: 'u2',
          turnId: 't2',
          sequence: 2,
          revision: 1,
          role: 'user',
          origin: 'human',
          text: 'Queued task',
        ),
        ConversationMessageModel(
          id: 'a1',
          turnId: 't1',
          sequence: 3,
          revision: 1,
          role: 'assistant',
          origin: 'provider',
          text: 'First answer',
        ),
        ConversationMessageModel(
          id: 'a2',
          turnId: 't2',
          sequence: 4,
          revision: 1,
          role: 'assistant',
          origin: 'provider',
          text: 'Queued answer',
        ),
      ],
);

void main() {
  group('mobile Chat timeline model', () {
    test(
      'keeps queued questions with their own answers instead of strict-sequence interleaving',
      () {
        final groups = groupConversationByTurn(snapshot());
        expect(
          groups
              .map((group) => group.items.map((item) => item.id).toList())
              .toList(),
          [
            ['u1', 'a1'],
            ['u2', 'a2'],
          ],
        );

        final markers = conversationMarkers(snapshot());
        expect(markers.map((marker) => marker.sequence), [1, 2]);
        expect(markers.map((marker) => marker.title), [
          'First task',
          'Queued task',
        ]);
        expect(markers.map((marker) => marker.detail), [
          'First answer',
          'Queued answer',
        ]);
      },
    );

    test(
      'keys a loaded turn by durable identity rather than its current page boundary',
      () {
        final withoutFirst = snapshot(
          items: snapshot().items.where((item) => item.id != 'u1').toList(),
        );
        expect(
          groupConversationByTurn(
            withoutFirst,
          ).firstWhere((group) => group.turnId == 't1').key,
          'turn-t1',
        );
        expect(
          groupConversationByTurn(
            snapshot(),
          ).firstWhere((group) => group.turnId == 't1').key,
          'turn-t1',
        );
      },
    );

    test('collects loose items with no turn into one trailing group', () {
      final loose = snapshot(
        items: [
          activity('system', 1, turnId: null),
          activity('system', 2, turnId: null),
        ],
      );
      final groups = groupConversationByTurn(loose);
      expect(groups, hasLength(1));
      expect(groups.single.key, 'loose-1');
      expect(groups.single.items, hasLength(2));
    });

    test(
      'filters usage, reasoning and duplicate plan rows without hiding unknown work',
      () {
        final planned = snapshot(
          turns: const [
            ConversationTurnModel(
              id: 't1',
              state: 'completed',
              providerTurnId: 'p1',
              requestedAt: '2026-08-05T00:00:00Z',
              planSteps: [PlanStepModel(text: 'Do it', status: 'pending')],
            ),
          ],
          items: [
            activity('usage', 5),
            activity('reasoning', 6),
            activity('plan', 7),
            activity('system', 8),
          ],
        );
        expect(readableConversationItems(planned).map((item) => item.id), [
          'system-8',
        ]);
      },
    );

    test('keeps a plan activity whose turn carries no plan of its own', () {
      final unplanned = snapshot(items: [activity('plan', 7)]);
      expect(readableConversationItems(unplanned).map((item) => item.id), [
        'plan-7',
      ]);
    });

    test('keeps a plan activity with an empty turn identifier', () {
      final planned = snapshot(
        turns: const [
          ConversationTurnModel(
            id: '',
            planSteps: [PlanStepModel(text: 'Do it', status: 'pending')],
          ),
        ],
        items: [activity('plan', 7, turnId: '')],
      );
      expect(readableConversationItems(planned).map((item) => item.id), [
        'plan-7',
      ]);
    });

    test('uses a truthy summary when activity detail text is empty', () {
      final empty = snapshot(
        items: [
          const ConversationMessageModel(
            id: 'u1',
            turnId: 't1',
            sequence: 1,
            role: 'user',
            origin: 'human',
            text: 'Question',
          ),
          const ConversationActivityModel(
            id: 'system-2',
            turnId: 't1',
            sequence: 2,
            activityKind: 'system',
            summary: 'Summary detail',
            detail: ActivityDetailModel({'text': ''}),
          ),
        ],
      );
      expect(conversationMarkers(empty).single.detail, 'Summary detail');
    });

    test('omits whitespace-only normalized activity marker detail', () {
      final whitespace = snapshot(
        items: [
          ConversationActivityModel(
            id: 'system-1',
            turnId: 't1',
            sequence: 1,
            revision: 1,
            activityKind: 'system',
            status: 'completed',
            detail: const ActivityDetailModel({'text': '   '}),
          ),
        ],
      );
      expect(conversationMarkers(whitespace).single.detail, isNull);
    });

    test(
      'gates rollback on the daemon capability, accepted history and idle state',
      () {
        final idle = snapshot();
        expect(canRollbackTurn(idle, idle.turns.first), isTrue);

        final busy = snapshot(
          turns: const [
            ConversationTurnModel(
              id: 't1',
              state: 'completed',
              providerTurnId: 'p1',
              requestedAt: 'a',
            ),
            ConversationTurnModel(
              id: 't2',
              state: 'running',
              providerTurnId: 'p2',
              requestedAt: 'b',
            ),
          ],
        );
        expect(canRollbackTurn(busy, busy.turns.first), isFalse);

        final uncapable = snapshot(capabilities: const []);
        expect(canRollbackTurn(uncapable, uncapable.turns.first), isFalse);

        final unaccepted = snapshot(
          turns: const [
            ConversationTurnModel(
              id: 't1',
              state: 'completed',
              requestedAt: 'a',
            ),
          ],
        );
        expect(canRollbackTurn(unaccepted, unaccepted.turns.first), isFalse);

        final already = snapshot(
          turns: const [
            ConversationTurnModel(
              id: 't1',
              state: 'completed',
              providerTurnId: 'p1',
              requestedAt: 'a',
              rolledBack: true,
            ),
          ],
        );
        expect(canRollbackTurn(already, already.turns.first), isFalse);
      },
    );

    test(
      'opens failed and live-output activities but keeps settled mechanics collapsed',
      () {
        expect(
          activityStartsExpanded(
            activity(
              'command',
              1,
              status: 'running',
              detail: {'output': 'tick'},
            ),
          ),
          isTrue,
        );
        expect(
          activityStartsExpanded(
            activity(
              'command',
              1,
              status: 'completed',
              detail: {'output': 'tick'},
            ),
          ),
          isFalse,
        );
        expect(
          activityStartsExpanded(activity('command', 1, status: 'failed')),
          isTrue,
        );
        expect(
          activityStartsExpanded(activity('command', 1, status: 'cancelled')),
          isFalse,
        );
        expect(
          activityStartsExpanded(activity('command', 1, status: 'running')),
          isFalse,
        );
      },
    );

    test('uses JavaScript truthiness for live activity bodies', () {
      for (final detail in [
        {'output': ''},
        {'output': false},
        {'output': 0},
        {'output': double.nan},
      ]) {
        expect(
          activityStartsExpanded(
            activity('command', 1, status: 'running', detail: detail),
          ),
          isFalse,
        );
      }
      for (final detail in [
        {'result': 'done'},
        {'error': 1},
        {'patchOutput': []},
        {'output': <String, dynamic>{}},
      ]) {
        expect(
          activityStartsExpanded(
            activity('command', 1, status: 'running', detail: detail),
          ),
          isTrue,
        );
      }
    });

    test(
      'builds nested provider work without hiding or looping malformed events',
      () {
        final parent = activity('command', 1, providerItemId: 'parent');
        final child = activity(
          'command',
          2,
          providerItemId: 'child',
          detail: {'parentProviderItemId': 'parent'},
        );
        final orphan = activity(
          'command',
          3,
          detail: {'parentProviderItemId': 'missing'},
        );

        final roots = activityHierarchy([parent, child, orphan]);
        expect(roots.map((node) => node.activity.id), [parent.id, orphan.id]);
        expect(roots.first.children.single.activity.id, child.id);
        expect(countActivityNodes(roots), 3);
        expect(activityNodesRunning(roots), isFalse);

        final running = activity(
          'command',
          2,
          status: 'running',
          providerItemId: 'child',
          detail: {'parentProviderItemId': 'parent'},
        );
        expect(
          activityNodesRunning(activityHierarchy([parent, running])),
          isTrue,
        );

        final cyclicParent = activity(
          'command',
          1,
          providerItemId: 'parent',
          detail: {'parentProviderItemId': 'child'},
        );
        expect(activityHierarchy([cyclicParent, child]), hasLength(2));
        expect(countActivityNodes(activityHierarchy([cyclicParent, child])), 2);
      },
    );
  });
}
