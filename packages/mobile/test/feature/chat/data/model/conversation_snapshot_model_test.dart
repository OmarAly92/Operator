import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';

Map<String, dynamic> wire({
  List<dynamic> messages = const [],
  List<dynamic> activities = const [],
  List<dynamic> turns = const [],
  Map<String, dynamic> extra = const {},
}) => {
  'conversationId': 'c-1',
  'sessionId': 'w-1',
  'harness': 'claude-code',
  'mode': 'chat',
  'controller': 'busy',
  'latestSequence': 2,
  'settings': <String, dynamic>{},
  'messages': messages,
  'activities': activities,
  'turns': turns,
  ...extra,
};

void main() {
  group('ConversationSnapshotModel', () {
    test(
      'maps the provider-neutral wire model without inventing protocol state',
      () {
        final snapshot = ConversationSnapshotModel.fromJson(
          wire(
            activities: [
              {
                'id': 'a-1',
                'sequence': 2,
                'revision': 1,
                'activityKind': 'approval',
                'status': 'pending',
                'summary': 'Run command',
                'requestId': 'req-1',
                'detail': {
                  'output': {'text': 'legacy'},
                  'decisions': [
                    {'id': 'accept'},
                    {'id': '', 'label': 'ignored'},
                    {'label': 'no id'},
                  ],
                },
                'createdAt': '2026-08-05T00:00:00Z',
              },
            ],
            extra: {
              'capabilities': ['config_options', 'steer'],
            },
          ),
        );

        expect(snapshot.controllerState, 'busy');
        expect(snapshot.capabilities, ['config_options', 'steer']);
        expect(snapshot.can('steer'), isTrue);
        expect(snapshot.can('rollback'), isFalse);

        final activity = snapshot.items.single as ConversationActivityModel;
        expect(activity.activityKind, 'approval');
        expect(activity.requestId, 'req-1');
        expect(activity.decisions, hasLength(1));
        expect(activity.decisions!.single.id, 'accept');
        expect(activity.decisions!.single.label, 'accept');
        expect(activity.detail!.output, {'text': 'legacy'});
        expect(activity.detail!.raw['output'], {'text': 'legacy'});
      },
    );

    test('leaves decisions absent rather than empty when none parse', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(
          activities: [
            {
              'id': 'a-1',
              'sequence': 1,
              'activityKind': 'approval',
              'status': 'pending',
              'detail': {'decisions': <dynamic>[]},
            },
          ],
        ),
      );
      expect(
        (snapshot.items.single as ConversationActivityModel).decisions,
        isNull,
      );
    });

    test('interleaves messages and activities by sequence', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(
          messages: [
            {
              'id': 'm-1',
              'sequence': 1,
              'role': 'user',
              'origin': 'human',
              'text': 'hi',
            },
            {
              'id': 'm-2',
              'sequence': 3,
              'role': 'assistant',
              'origin': 'provider',
              'text': 'done',
            },
          ],
          activities: [
            {
              'id': 'a-1',
              'sequence': 2,
              'activityKind': 'command',
              'status': 'completed',
              'summary': 'ls',
            },
          ],
        ),
      );
      expect(snapshot.items.map((item) => item.id), ['m-1', 'a-1', 'm-2']);
      expect(snapshot.items.first, isA<ConversationMessageModel>());
      expect(snapshot.items[1], isA<ConversationActivityModel>());
      expect(snapshot.items.first.itemKey, 'message:m-1');
      expect(snapshot.items[1].itemKey, 'activity:a-1');
    });

    test('treats a missing oldestSequence as one past the newest row', () {
      expect(ConversationSnapshotModel.fromJson(wire()).oldestSequence, 3);
      expect(ConversationSnapshotModel.fromJson(wire()).hasMoreBefore, isFalse);
      expect(
        ConversationSnapshotModel.fromJson(
          wire(extra: {'oldestSequence': 1, 'hasMoreBefore': true}),
        ).oldestSequence,
        1,
      );
    });

    test(
      'drops empty setting strings so the picker shows the provider default',
      () {
        final snapshot = ConversationSnapshotModel.fromJson(
          wire(
            extra: {
              'settings': {
                'model': '',
                'reasoningEffort': 'high',
                'approvalMode': '',
              },
            },
          ),
        );
        expect(snapshot.settings.model, isNull);
        expect(snapshot.settings.reasoningEffort, 'high');
        expect(snapshot.settings.approvalMode, isNull);
      },
    );

    test('reads turn plans, diffs and lifecycle helpers', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(
          turns: [
            {
              'id': 't-1',
              'state': 'completed',
              'providerTurnId': 'p-1',
              'requestedAt': '2026-08-05T00:00:00Z',
            },
            {
              'id': 't-2',
              'state': 'running',
              'requestedAt': '2026-08-05T00:00:01Z',
              'plan': {
                'explanation': 'why',
                'steps': [
                  {'text': 'Do it', 'status': 'in_progress'},
                ],
              },
              'diff': {
                'truncated': true,
                'files': [
                  {
                    'path': 'a.dart',
                    'status': 'added',
                    'additions': 3,
                    'deletions': 0,
                  },
                  {'path': 'b.dart', 'status': 'nonsense'},
                ],
              },
            },
          ],
        ),
      );

      expect(snapshot.activeTurn?.id, 't-2');
      expect(snapshot.hasTurnInFlight, isTrue);
      expect(snapshot.turns[1].planSteps.single.text, 'Do it');
      expect(snapshot.turns[1].planExplanation, 'why');
      expect(snapshot.turns[1].hasPlan, isTrue);
      expect(snapshot.turns[1].diffTruncated, isTrue);
      expect(snapshot.turns[1].diffFiles.first.additions, 3);
      expect(snapshot.turns[1].diffFiles[1].status, 'modified');
      expect(snapshot.turns[0].hasPlan, isFalse);
    });

    test('prefers a running turn but accepts a queued one', () {
      final queued = ConversationSnapshotModel.fromJson(
        wire(
          turns: [
            {
              'id': 't-1',
              'state': 'completed',
              'requestedAt': '2026-08-05T00:00:00Z',
            },
            {
              'id': 't-2',
              'state': 'queued',
              'requestedAt': '2026-08-05T00:00:01Z',
            },
          ],
        ),
      );
      expect(queued.activeTurn?.id, 't-2');
      expect(queued.hasTurnInFlight, isTrue);
    });

    test('reports pending requests and broken MCP servers', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(
          activities: [
            {
              'id': 'a-1',
              'sequence': 1,
              'activityKind': 'user_input',
              'status': 'pending',
              'summary': 'Sign in',
            },
          ],
          extra: {
            'mcpServers': [
              {'name': 'github', 'status': 'failed', 'error': 'token expired'},
              {'name': 'fs', 'status': 'ready'},
            ],
          },
        ),
      );
      expect(snapshot.hasPendingRequest, isTrue);
      expect(snapshot.brokenMcpServers.map((server) => server.name), [
        'github',
      ]);
    });

    test('parses the elicitation schema the input card renders', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(
          activities: [
            {
              'id': 'a-1',
              'sequence': 1,
              'activityKind': 'user_input',
              'status': 'pending',
              'summary': 'Sign in',
              'detail': {
                'inputMode': 'form',
                'schema': {
                  'title': 'Credentials',
                  'required': ['token'],
                  'properties': {
                    'token': {
                      'type': 'string',
                      'title': 'Token',
                      'minLength': 8,
                    },
                    'scopes': {
                      'type': 'array',
                      'items': {
                        'anyOf': [
                          {'const': 'read', 'title': 'Read'},
                          {'const': 'write'},
                        ],
                      },
                    },
                  },
                },
              },
            },
          ],
        ),
      );

      final schema =
          (snapshot.items.single as ConversationActivityModel).detail!.schema!;
      expect(schema.title, 'Credentials');
      expect(schema.required, ['token']);
      expect(schema.properties['token']!.minLength, 8);
      expect(
        schema.properties['scopes']!.itemsAnyOf!.map((choice) => choice.label),
        ['Read', 'write'],
      );
    });

    test(
      'distinguishes an absent elicitation default from an explicit null',
      () {
        final absent = InputPropertyModel.fromJson({'type': 'boolean'});
        final explicitNull = InputPropertyModel.fromJson({
          'type': 'boolean',
          'default': null,
        });

        expect(absent.hasDefaultValue, isFalse);
        expect(explicitNull.hasDefaultValue, isTrue);
        expect(explicitNull.defaultValue, isNull);
      },
    );

    test('keeps omitted wire scalars nullable and collections non-null', () {
      final snapshot = ConversationSnapshotModel.fromJson({
        'messages': [<String, dynamic>{}],
        'turns': [<String, dynamic>{}],
      });

      expect(snapshot.conversationId, isNull);
      expect(snapshot.items.single.id, isNull);
      expect(snapshot.items.single.sequence, isNull);
      expect(snapshot.turns.single.id, isNull);
      expect(snapshot.turns.single.diffFiles, isEmpty);
      expect(snapshot.capabilities, isEmpty);
    });

    test('copyWith replaces only what pagination merges', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire());
      final merged = snapshot.copyWith(
        oldestSequence: 1,
        hasMoreBefore: true,
        items: const [],
        turns: const [],
      );
      expect(merged.oldestSequence, 1);
      expect(merged.hasMoreBefore, isTrue);
      expect(merged.conversationId, 'c-1');
      expect(merged.harness, 'claude-code');
    });
  });
}
