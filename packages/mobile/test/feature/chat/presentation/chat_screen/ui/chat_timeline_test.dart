import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart';

ConversationSnapshotModel snapshot({
  List<ConversationItemModel> items = const [],
  List<ConversationTurnModel> turns = const [],
  bool hasMoreBefore = false,
  List<String> capabilities = const [],
}) => ConversationSnapshotModel(
  conversationId: 'c-1',
  sessionId: 'w-1',
  harness: 'codex',
  controllerState: 'ready',
  latestSequence: 9,
  hasMoreBefore: hasMoreBefore,
  items: items,
  turns: turns,
  capabilities: capabilities,
);

Future<void> pumpTimeline(
  WidgetTester tester,
  ConversationSnapshotModel value, {
  int? jumpToSequence,
  VoidCallback? onJumpHandled,
  Future<int> Function(String turnId)? onRollback,
}) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: ChatTimeline(
              snapshot: value,
              loadingOlder: false,
              onLoadOlder: () {},
              approvalPending: false,
              inputPending: false,
              onDecide: (requestId, decisionId) async {},
              onResolveInput: (requestId, action, [content]) async {},
              onRollback: onRollback ?? (_) async => 0,
              jumpToSequence: jumpToSequence,
              onJumpHandled: onJumpHandled,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invites the first message on an empty conversation', (
    tester,
  ) async {
    await pumpTimeline(tester, snapshot());
    expect(find.text('Start the conversation'), findsOneWidget);
  });

  testWidgets('renders a human message and an assistant answer differently', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(
            id: 'u1',
            sequence: 1,
            revision: 1,
            role: 'user',
            origin: 'human',
            text: 'do the thing',
          ),
          ConversationMessageModel(
            id: 'a1',
            sequence: 2,
            revision: 1,
            role: 'assistant',
            origin: 'provider',
            text: 'Done.',
          ),
        ],
      ),
    );

    expect(find.text('do the thing'), findsOneWidget);
    expect(find.text('Done.'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('warns about an unconfirmed delivery', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(
            id: 'u1',
            sequence: 1,
            revision: 1,
            role: 'user',
            origin: 'human',
            text: 'hi',
            delivery: 'uncertain',
          ),
        ],
      ),
    );
    expect(find.textContaining('Delivery unconfirmed'), findsOneWidget);
  });

  testWidgets('summarizes a run of mechanics instead of listing each one', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: [
          for (var index = 1; index <= 3; index++)
            ConversationActivityModel(
              id: 'c$index',
              turnId: 't1',
              sequence: index,
              revision: 1,
              activityKind: 'command',
              status: 'completed',
              summary: 'cat file$index.dart',
              detail: ActivityDetailModel({'command': 'cat file$index.dart'}),
            ),
        ],
      ),
    );

    expect(find.text('Explored 3 files'), findsOneWidget);
    expect(find.textContaining('cat file1.dart'), findsNothing);
  });

  testWidgets('expands a failed activity by default', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: [
          ConversationActivityModel(
            id: 'c1',
            turnId: 't1',
            sequence: 1,
            revision: 1,
            activityKind: 'command',
            status: 'failed',
            summary: 'npm test',
            detail: ActivityDetailModel(const {
              'command': 'npm test',
              'output': 'boom',
            }),
          ),
        ],
      ),
    );
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('shows a turn plan with its progress count', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(
            id: 'u1',
            turnId: 't1',
            sequence: 1,
            revision: 1,
            role: 'user',
            text: 'go',
          ),
        ],
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'completed',
            requestedAt: '2026-08-05T00:00:00Z',
            planSteps: [
              PlanStepModel(text: 'Read the code', status: 'completed'),
              PlanStepModel(text: 'Change it', status: 'pending'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets('offers rollback only when the daemon allows it', (tester) async {
    const turn = ConversationTurnModel(
      id: 't1',
      state: 'completed',
      providerTurnId: 'p1',
      requestedAt: '2026-08-05T00:00:00Z',
    );
    const item = ConversationMessageModel(
      id: 'u1',
      turnId: 't1',
      sequence: 1,
      revision: 1,
      role: 'user',
      text: 'go',
    );

    await pumpTimeline(
      tester,
      snapshot(items: const [item], turns: const [turn]),
    );
    expect(find.byIcon(Icons.settings_backup_restore), findsNothing);

    await pumpTimeline(
      tester,
      snapshot(
        items: const [item],
        turns: const [turn],
        capabilities: const ['rollback'],
      ),
    );
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
  });

  testWidgets('confirms rollback before invoking the daemon action', (
    tester,
  ) async {
    final rolledBack = <String>[];
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(
            id: 'u1',
            turnId: 't1',
            sequence: 1,
            revision: 1,
            role: 'user',
            text: 'go',
          ),
        ],
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'completed',
            providerTurnId: 'p1',
            requestedAt: '2026-08-05T00:00:00Z',
          ),
        ],
        capabilities: const ['rollback'],
      ),
      onRollback: (turnId) async {
        rolledBack.add(turnId);
        return 4;
      },
    );

    await tester.tap(find.byIcon(Icons.settings_backup_restore));
    await tester.pump();
    expect(find.textContaining('Make the agent forget'), findsOneWidget);
    expect(rolledBack, isEmpty);

    await tester.tap(find.text('Roll back'));
    await tester.pumpAndSettle();
    expect(rolledBack, ['t1']);
  });

  testWidgets('offers to load earlier messages only when there are any', (
    tester,
  ) async {
    await pumpTimeline(tester, snapshot(hasMoreBefore: true));
    expect(find.text('Load earlier messages'), findsOneWidget);
  });

  testWidgets('starts at the latest exchange when the timeline is long', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: [
          for (var index = 1; index <= 30; index++)
            ConversationMessageModel(
              id: 'm$index',
              turnId: 't$index',
              sequence: index,
              revision: 1,
              role: 'assistant',
              text: 'Answer $index ${'detail ' * 12}',
            ),
        ],
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.controller!.position.pixels,
      list.controller!.position.maxScrollExtent,
    );
    expect(find.textContaining('Answer 30'), findsOneWidget);
  });

  testWidgets(
    'jumps to a distant exchange selected from the conversation map',
    (tester) async {
      var handled = 0;
      await pumpTimeline(
        tester,
        snapshot(
          items: [
            for (var index = 1; index <= 30; index++)
              ConversationMessageModel(
                id: 'm$index',
                turnId: 't$index',
                sequence: index,
                revision: 1,
                role: 'assistant',
                text: 'Mapped answer $index ${'detail ' * 12}',
              ),
          ],
        ),
        jumpToSequence: 20,
        onJumpHandled: () => handled++,
      );

      expect(find.textContaining('Mapped answer 20'), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);
      expect(handled, 1);
    },
  );

  testWidgets('shows Latest after the user moves more than 120 pixels away', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: [
          for (var index = 1; index <= 30; index++)
            ConversationMessageModel(
              id: 'm$index',
              turnId: 't$index',
              sequence: index,
              revision: 1,
              role: 'assistant',
              text: 'Scrollable answer $index ${'detail ' * 12}',
            ),
        ],
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);

    await tester.tap(find.text('Latest'));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.controller!.position.pixels,
      list.controller!.position.maxScrollExtent,
    );
    expect(find.text('Latest'), findsNothing);
  });

  test('summarizes activity categories the way the desktop does', () {
    ConversationActivityModel command(String summary) =>
        ConversationActivityModel(
          id: summary,
          sequence: 1,
          revision: 1,
          activityKind: 'command',
          status: 'completed',
          summary: summary,
        );

    expect(
      summarizeActivities([command('cat a'), command('rg foo')]),
      'Explored 1 file, 1 search',
    );
    expect(summarizeActivities([command('git status')]), 'Ran 1 git check');
    expect(summarizeActivities([command('npm test')]), 'Ran 1 command');
  });

  test('keeps human-visible activity boundaries out of collapsed runs', () {
    ConversationActivityModel activity(
      String id,
      String kind, {
      String turnId = 't1',
      ActivityDetailModel? detail,
    }) => ConversationActivityModel(
      id: id,
      turnId: turnId,
      sequence: int.parse(id.substring(1)),
      revision: 1,
      activityKind: kind,
      status: 'completed',
      summary: id,
      detail: detail,
    );

    final rows = activityRuns([
      activity('a1', 'command'),
      activity('a2', 'command'),
      activity('a3', 'approval'),
      activity('a4', 'command'),
      activity('a5', 'file_change'),
      activity(
        'a6',
        'command',
        detail: const ActivityDetailModel({'event': 'steer'}),
      ),
      activity('a7', 'command', turnId: 't2'),
    ]);

    expect(rows, hasLength(6));
    expect((rows[0] as ActivitiesRow).activities, hasLength(2));
    expect(rows[1], isA<SingleRow>());
    expect((rows[2] as ActivitiesRow).activities, hasLength(1));
    expect(rows[3], isA<SingleRow>());
    expect(rows[4], isA<SingleRow>());
    expect((rows[5] as ActivitiesRow).activities.single.turnId, 't2');
  });

  test('summarizes tools reviews plans and plural categories', () {
    ConversationActivityModel activity(String id, String kind) =>
        ConversationActivityModel(
          id: id,
          sequence: 1,
          revision: 1,
          activityKind: kind,
          status: 'completed',
          summary: id,
        );

    expect(
      summarizeActivities([
        activity('tool-1', 'mcp_tool'),
        activity('tool-2', 'mcp_tool'),
        activity('review-1', 'auto_review'),
        activity('review-2', 'auto_review'),
        activity('plan-1', 'plan'),
      ]),
      'Ran 2 tool calls, 2 auto-decisions, updated plan',
    );
  });
}
