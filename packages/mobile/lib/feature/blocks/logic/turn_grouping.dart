import 'package:equatable/equatable.dart';
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

int? _durationBetween(String? startedAt, String? completedAt) {
  if (startedAt == null || completedAt == null) return null;
  final start = DateTime.tryParse(startedAt);
  final end = DateTime.tryParse(completedAt);
  if (start == null || end == null) return null;
  return end.difference(start).inMilliseconds.clamp(0, 1 << 53);
}
