### Task 13: Timeline model (`timelineModel.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/timeline_model.dart`
- Test: `packages/mobile/test/feature/chat/logic/timeline_model_test.dart`

**Interfaces:**
- Consumes: the Task 11 models.
- Produces:
  - `class ConversationGroup extends Equatable` — `key`, `turnId`, `anchor (int)`,
    `items (List<ConversationItemModel>)`, `turn (ConversationTurnModel?)`
  - `class ConversationMarker extends Equatable` — `key`, `sequence (int)`, `title`,
    `detail (String?)`, `state (String?)`
  - `class ActivityNode` — `activity (ConversationActivityModel)`, `children (List<ActivityNode>)`
  - `List<ConversationItemModel> readableConversationItems(ConversationSnapshotModel snapshot)`
  - `List<ConversationGroup> groupConversationByTurn(ConversationSnapshotModel snapshot, [List<ConversationItemModel>? items])`
  - `List<ConversationMarker> conversationMarkers(ConversationSnapshotModel snapshot)`
  - `bool canRollbackTurn(ConversationSnapshotModel snapshot, ConversationTurnModel turn)`
  - `bool activityStartsExpanded(ConversationActivityModel activity)`
  - `List<ActivityNode> activityHierarchy(List<ConversationActivityModel> activities)`
  - `int countActivityNodes(List<ActivityNode> nodes)`
  - `bool activityNodesRunning(List<ActivityNode> nodes)`

Three rules here are load-bearing and are exactly what the mirrored test pins:

- A turn remains **one readable exchange** even when queued-message sequencing interleaves it with
  the turn currently running. This is presentation grouping over daemon-owned sequence and turn
  identities, never inferred lifecycle state.
- A group's key is `turn-<turnId>`, its **durable** identity. The first loaded item can move
  backward when an older page arrives; the turn id cannot. Keying on the item would reset expanded
  rows and scroll position on every pagination.
- `activityHierarchy` reconstructs provider-owned nested agent work without inventing lifecycle
  state. Unknown parents and malformed cycles stay visible as roots rather than disappearing.

Usage and reasoning rows are filtered out of the mobile timeline: they remain in the durable
record, but prose and work are the primary surface on a phone. A `plan` activity is dropped only
when its own turn already carries a plan, so the same plan is not rendered twice.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/timeline_model_test.dart` (ported from
`chat/timelineModel.test.ts`):

```dart
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
}) =>
    ConversationActivityModel(
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
}) =>
    ConversationSnapshotModel(
      conversationId: 'c',
      sessionId: 's',
      harness: 'codex',
      mode: 'chat',
      controllerState: 'ready',
      latestSequence: 4,
      oldestSequence: 1,
      capabilities: capabilities,
      turns: turns ??
          const [
            ConversationTurnModel(
                id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: '2026-08-05T00:00:00Z'),
            ConversationTurnModel(
                id: 't2', state: 'completed', providerTurnId: 'p2', requestedAt: '2026-08-05T00:00:01Z'),
          ],
      items: items ??
          const [
            ConversationMessageModel(
                id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', origin: 'human', text: 'First task'),
            ConversationMessageModel(
                id: 'u2', turnId: 't2', sequence: 2, revision: 1, role: 'user', origin: 'human', text: 'Queued task'),
            ConversationMessageModel(
                id: 'a1',
                turnId: 't1',
                sequence: 3,
                revision: 1,
                role: 'assistant',
                origin: 'provider',
                text: 'First answer'),
            ConversationMessageModel(
                id: 'a2',
                turnId: 't2',
                sequence: 4,
                revision: 1,
                role: 'assistant',
                origin: 'provider',
                text: 'Queued answer'),
          ],
    );

void main() {
  group('mobile Chat timeline model', () {
    test('keeps queued questions with their own answers instead of strict-sequence interleaving', () {
      final groups = groupConversationByTurn(snapshot());
      expect(
        groups.map((group) => group.items.map((item) => item.id).toList()).toList(),
        [
          ['u1', 'a1'],
          ['u2', 'a2'],
        ],
      );

      final markers = conversationMarkers(snapshot());
      expect(markers.map((marker) => marker.sequence), [1, 2]);
      expect(markers.map((marker) => marker.title), ['First task', 'Queued task']);
      expect(markers.map((marker) => marker.detail), ['First answer', 'Queued answer']);
    });

    test('keys a loaded turn by durable identity rather than its current page boundary', () {
      final withoutFirst = snapshot(
        items: snapshot().items.where((item) => item.id != 'u1').toList(),
      );
      expect(
        groupConversationByTurn(withoutFirst).firstWhere((group) => group.turnId == 't1').key,
        'turn-t1',
      );
      expect(
        groupConversationByTurn(snapshot()).firstWhere((group) => group.turnId == 't1').key,
        'turn-t1',
      );
    });

    test('collects loose items with no turn into one trailing group', () {
      final loose = snapshot(items: [
        activity('system', 1, turnId: null),
        activity('system', 2, turnId: null),
      ]);
      final groups = groupConversationByTurn(loose);
      expect(groups, hasLength(1));
      expect(groups.single.key, 'loose-1');
      expect(groups.single.items, hasLength(2));
    });

    test('filters usage, reasoning and duplicate plan rows without hiding unknown work', () {
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
      expect(readableConversationItems(planned).map((item) => item.id), ['system-8']);
    });

    test('keeps a plan activity whose turn carries no plan of its own', () {
      final unplanned = snapshot(items: [activity('plan', 7)]);
      expect(readableConversationItems(unplanned).map((item) => item.id), ['plan-7']);
    });

    test('gates rollback on the daemon capability, accepted history and idle state', () {
      final idle = snapshot();
      expect(canRollbackTurn(idle, idle.turns.first), isTrue);

      final busy = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: 'a'),
        ConversationTurnModel(id: 't2', state: 'running', providerTurnId: 'p2', requestedAt: 'b'),
      ]);
      expect(canRollbackTurn(busy, busy.turns.first), isFalse);

      final uncapable = snapshot(capabilities: const []);
      expect(canRollbackTurn(uncapable, uncapable.turns.first), isFalse);

      final unaccepted = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', requestedAt: 'a'),
      ]);
      expect(canRollbackTurn(unaccepted, unaccepted.turns.first), isFalse);

      final already = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: 'a', rolledBack: true),
      ]);
      expect(canRollbackTurn(already, already.turns.first), isFalse);
    });

    test('opens failed and live-output activities but keeps settled mechanics collapsed', () {
      expect(
        activityStartsExpanded(activity('command', 1, status: 'running', detail: {'output': 'tick'})),
        isTrue,
      );
      expect(
        activityStartsExpanded(activity('command', 1, status: 'completed', detail: {'output': 'tick'})),
        isFalse,
      );
      expect(activityStartsExpanded(activity('command', 1, status: 'failed')), isTrue);
      expect(activityStartsExpanded(activity('command', 1, status: 'cancelled')), isFalse);
      expect(activityStartsExpanded(activity('command', 1, status: 'running')), isFalse);
    });

    test('builds nested provider work without hiding or looping malformed events', () {
      final parent = activity('command', 1, providerItemId: 'parent');
      final child = activity('command', 2, providerItemId: 'child', detail: {'parentProviderItemId': 'parent'});
      final orphan = activity('command', 3, detail: {'parentProviderItemId': 'missing'});

      final roots = activityHierarchy([parent, child, orphan]);
      expect(roots.map((node) => node.activity.id), [parent.id, orphan.id]);
      expect(roots.first.children.single.activity.id, child.id);
      expect(countActivityNodes(roots), 3);
      expect(activityNodesRunning(roots), isFalse);

      final running = activity('command', 2, status: 'running', providerItemId: 'child', detail: {
        'parentProviderItemId': 'parent',
      });
      expect(activityNodesRunning(activityHierarchy([parent, running])), isTrue);

      final cyclicParent =
          activity('command', 1, providerItemId: 'parent', detail: {'parentProviderItemId': 'child'});
      expect(activityHierarchy([cyclicParent, child]), hasLength(2));
      expect(countActivityNodes(activityHierarchy([cyclicParent, child])), 2);
    });
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/timeline_model_test.dart`
Expected: FAIL — the library does not exist.

- [x] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/timeline_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

final RegExp _fence = RegExp(r'```[\s\S]*?```');
final RegExp _link = RegExp(r'\[([^\]]+)]\([^)]*\)');
final RegExp _marks = RegExp(r'[*_`#>~]+');
final RegExp _whitespaceRun = RegExp(r'\s+');

class ConversationGroup extends Equatable {
  const ConversationGroup({
    required this.key,
    required this.anchor,
    required this.items,
    this.turnId,
    this.turn,
  });

  final String key;
  final String? turnId;
  final int anchor;
  final List<ConversationItemModel> items;
  final ConversationTurnModel? turn;

  @override
  List<Object?> get props => [key, turnId, anchor, items, turn];
}

class ConversationMarker extends Equatable {
  const ConversationMarker({
    required this.key,
    required this.sequence,
    required this.title,
    this.detail,
    this.state,
  });

  final String key;
  final int sequence;
  final String title;
  final String? detail;
  final String? state;

  @override
  List<Object?> get props => [key, sequence, title, detail, state];
}

class ActivityNode {
  ActivityNode(this.activity);

  final ConversationActivityModel activity;
  final List<ActivityNode> children = [];
}

List<ConversationItemModel> readableConversationItems(ConversationSnapshotModel snapshot) {
  final plannedTurns = snapshot.turns.where((turn) => turn.hasPlan).map((turn) => turn.id).toSet();
  return snapshot.items.where((item) {
    if (item is! ConversationActivityModel) return true;
    if (item.activityKind == 'usage' || item.activityKind == 'reasoning') return false;
    return !(item.activityKind == 'plan' && item.turnId != null && plannedTurns.contains(item.turnId));
  }).toList();
}

List<ConversationGroup> groupConversationByTurn(
  ConversationSnapshotModel snapshot, [
  List<ConversationItemModel>? items,
]) {
  final rows = items ?? readableConversationItems(snapshot);
  final turns = {for (final turn in snapshot.turns) turn.id: turn};
  final byTurn = <String, List<ConversationItemModel>>{};
  final groups = <ConversationGroup>[];
  final looseItems = <int, List<ConversationItemModel>>{};

  for (final item in rows) {
    final turnId = item.turnId;
    if (turnId == null) {
      final previous = groups.isEmpty ? null : groups.last;
      if (previous != null && previous.turnId == null) {
        looseItems[previous.anchor]!.add(item);
      } else {
        final bucket = <ConversationItemModel>[item];
        looseItems[item.sequence] = bucket;
        groups.add(ConversationGroup(key: 'loose-${item.sequence}', anchor: item.sequence, items: bucket));
      }
      continue;
    }

    final existing = byTurn[turnId];
    if (existing != null) {
      existing.add(item);
      continue;
    }
    final bucket = <ConversationItemModel>[item];
    byTurn[turnId] = bucket;
    groups.add(ConversationGroup(
      key: 'turn-$turnId',
      turnId: turnId,
      anchor: item.sequence,
      items: bucket,
      turn: turns[turnId],
    ));
  }

  return groups..sort((left, right) => left.anchor.compareTo(right.anchor));
}

List<ConversationMarker> conversationMarkers(ConversationSnapshotModel snapshot) =>
    groupConversationByTurn(snapshot).map((group) {
      final human = group.items
          .whereType<ConversationMessageModel>()
          .where((item) => item.role == 'user' && item.origin == 'human')
          .firstOrNull;
      final assistant = group.items.reversed
          .whereType<ConversationMessageModel>()
          .where((item) => item.role == 'assistant' && item.text.trim().isNotEmpty)
          .firstOrNull;
      final activity = group.items.whereType<ConversationActivityModel>().firstOrNull;

      final title = _previewText(
        human?.text ?? (activity?.summary.isNotEmpty == true ? activity!.summary : 'Conversation update'),
        120,
      );
      final detailSource = assistant?.text ?? activity?.detail?.text ?? activity?.summary;
      final detail = detailSource == null || detailSource.isEmpty ? null : _previewText(detailSource, 240);

      return ConversationMarker(
        key: group.key,
        sequence: group.anchor,
        title: title,
        detail: detail != null && detail != title ? detail : null,
        state: group.turn?.state,
      );
    }).toList();

bool canRollbackTurn(ConversationSnapshotModel snapshot, ConversationTurnModel turn) =>
    snapshot.can('rollback') &&
    !snapshot.hasTurnInFlight &&
    !turn.isInFlight &&
    turn.providerTurnId != null &&
    !turn.rolledBack;

bool activityStartsExpanded(ConversationActivityModel activity) {
  final detail = activity.detail;
  final liveBody = activity.status == 'running' &&
      (detail?.output != null ||
          detail?.result != null ||
          detail?.error != null ||
          detail?.patchOutput != null);
  return activity.status == 'failed' || liveBody;
}

List<ActivityNode> activityHierarchy(List<ConversationActivityModel> activities) {
  final byProvider = <String, ActivityNode>{};
  final nodes = activities.map((activity) {
    final node = ActivityNode(activity);
    final providerItemId = activity.providerItemId;
    if (providerItemId != null) byProvider[providerItemId] = node;
    return node;
  }).toList();

  final roots = <ActivityNode>[];
  for (final node in nodes) {
    final parentId = node.activity.detail?.parentProviderItemId;
    final parent = parentId == null ? null : byProvider[parentId];
    if (parent != null && !_activityCycle(node, parent, byProvider)) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

int countActivityNodes(List<ActivityNode> nodes) =>
    nodes.fold(0, (count, node) => count + 1 + countActivityNodes(node.children));

bool activityNodesRunning(List<ActivityNode> nodes) =>
    nodes.any((node) => node.activity.status == 'running' || activityNodesRunning(node.children));

bool _activityCycle(ActivityNode node, ActivityNode parent, Map<String, ActivityNode> byProvider) {
  final visited = <ActivityNode>{node};
  ActivityNode? current = parent;
  while (current != null) {
    if (visited.contains(current)) return true;
    visited.add(current);
    final parentId = current.activity.detail?.parentProviderItemId;
    current = parentId == null ? null : byProvider[parentId];
  }
  return false;
}

String _previewText(String value, int limit) {
  final plain = value
      .replaceAll(_fence, ' code sample ')
      .replaceAllMapped(_link, (match) => match.group(1)!)
      .replaceAll(_marks, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  return plain.length > limit ? '${plain.substring(0, limit - 1).trimRight()}…' : plain;
}
```

`firstOrNull` comes from `dart:collection`'s `IterableExtension`, which Flutter re-exports through
`package:flutter/foundation.dart`'s `collection` dependency. If the analyzer cannot resolve it, add
`import 'package:collection/collection.dart';` — `collection` is already a transitive dependency of
`flutter_test` and `equatable`.

- [x] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/timeline_model_test.dart`
Expected: PASS.

- [x] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 483/483 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the chat timeline model"
```

---
