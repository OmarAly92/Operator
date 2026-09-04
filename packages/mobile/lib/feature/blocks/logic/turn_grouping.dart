import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class TurnGroup extends Equatable {
  const TurnGroup({
    this.turnId,
    required this.blocks,
    this.startedAt,
    this.completedAt,
    this.durationMs,
    required this.running,
    this.model,
  });

  final String? turnId;
  final List<SessionBlock> blocks;
  final String? startedAt;
  final String? completedAt;
  final int? durationMs;
  final bool running;
  final String? model;

  @override
  List<Object?> get props => [
    turnId,
    blocks,
    startedAt,
    completedAt,
    durationMs,
    running,
    model,
  ];
}

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

List<ConversationItemModel> readableConversationItems(
  ConversationSnapshotModel snapshot,
) {
  final plannedTurns = snapshot.turns
      .where((turn) => turn.hasPlan)
      .map((turn) => turn.id)
      .whereType<String>()
      .toSet();
  return snapshot.items.where((item) {
    if (item is! ConversationActivityModel) return true;
    if (item.activityKind == 'usage' || item.activityKind == 'reasoning') {
      return false;
    }
    return !(item.activityKind == 'plan' &&
        (item.turnId?.isNotEmpty ?? false) &&
        plannedTurns.contains(item.turnId));
  }).toList();
}

bool continuesTurn(SessionBlock previous, SessionBlock current) {
  if (previous.turnId != null && current.turnId != null) {
    return previous.turnId == current.turnId;
  }
  return current.kind != BlockKind.prompt;
}

bool continuesResponse(SessionBlock _, SessionBlock current) =>
    current.kind != BlockKind.prompt;

List<TurnGroup> groupBlocksByTurn(List<SessionBlock> blocks, {bool sessionActive = false}) {
  final groups = <TurnGroup>[];
  for (final block in blocks) {
    final group = groups.isEmpty ? null : groups.last;
    if (group != null && continuesTurn(group.blocks.last, block)) {
      group.blocks.add(block);
      continue;
    }
    groups.add(
      TurnGroup(
        turnId: block.turnId,
        blocks: [block],
        startedAt: block.createdAt,
        running: false,
      ),
    );
  }

  final result = groups.map((group) {
    final last = group.blocks.last;
    bool running = false;
    String? lastChildCreatedAt;
    for (final block in group.blocks) {
      if (block.status == BlockStatus.running) running = true;
      for (final child in block.children ?? const <SessionBlock>[]) {
        if (child.status == BlockStatus.running) running = true;
        final childCreatedAt = child.createdAt;
        if (childCreatedAt != null) {
          if (lastChildCreatedAt == null || childCreatedAt.compareTo(lastChildCreatedAt) > 0) {
            lastChildCreatedAt = childCreatedAt;
          }
        }
      }
    }
    final lastCreatedAt = last.createdAt;
    final String? completedAt;
    if (running) {
      completedAt = null;
    } else if (lastChildCreatedAt != null &&
        (lastCreatedAt == null || lastChildCreatedAt.compareTo(lastCreatedAt) > 0)) {
      completedAt = lastChildCreatedAt;
    } else {
      completedAt = lastCreatedAt;
    }
    return TurnGroup(
      turnId: group.turnId,
      blocks: group.blocks,
      startedAt: group.startedAt,
      completedAt: completedAt,
      durationMs: _durationBetween(group.startedAt, completedAt),
      running: running,
      model: _groupModel(group.blocks),
    );
  }).toList();

  if (!sessionActive || result.isEmpty || result.last.running) return result;
  final last = result.last;
  result[result.length - 1] = TurnGroup(
    turnId: last.turnId,
    blocks: last.blocks,
    startedAt: last.startedAt,
    running: true,
    model: last.model,
  );
  return result;
}

String? _groupModel(List<SessionBlock> blocks) {
  for (final block in blocks) {
    final model = block.model;
    if (model != null && model.isNotEmpty) return model;
  }
  return null;
}

List<ConversationGroup> groupConversationByTurn(
  ConversationSnapshotModel snapshot, [
  List<ConversationItemModel>? items,
]) {
  final rows = items ?? readableConversationItems(snapshot);
  final turns = {
    for (final turn in snapshot.turns)
      if (turn.id != null) turn.id!: turn,
  };
  final byTurn = <String, ConversationGroup>{};
  final groups = <ConversationGroup>[];

  for (final item in rows) {
    final turnId = item.turnId;
    if (turnId == null || turnId.isEmpty) {
      final previous = groups.isEmpty ? null : groups.last;
      if (previous != null && previous.turnId == null) {
        previous.items.add(item);
      } else {
        groups.add(
          ConversationGroup(
            key: 'loose-${item.sequence ?? 0}',
            anchor: item.sequence ?? 0,
            items: [item],
          ),
        );
      }
      continue;
    }

    final existing = byTurn[turnId];
    if (existing != null) {
      existing.items.add(item);
      continue;
    }
    final group = ConversationGroup(
      key: 'turn-$turnId',
      turnId: turnId,
      anchor: item.sequence ?? 0,
      items: [item],
      turn: turns[turnId],
    );
    byTurn[turnId] = group;
    groups.add(group);
  }

  return groups..sort((left, right) => left.anchor.compareTo(right.anchor));
}

int? _durationBetween(String? startedAt, String? completedAt) {
  if (startedAt == null || completedAt == null) return null;
  final start = DateTime.tryParse(startedAt);
  final end = DateTime.tryParse(completedAt);
  if (start == null || end == null) return null;
  return end.difference(start).inMilliseconds.clamp(0, 1 << 53);
}
