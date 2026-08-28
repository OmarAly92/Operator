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
  });

  final String? turnId;
  final List<SessionBlock> blocks;
  final String? startedAt;
  final String? completedAt;
  final int? durationMs;
  final bool running;

  @override
  List<Object?> get props => [
    turnId,
    blocks,
    startedAt,
    completedAt,
    durationMs,
    running,
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

List<TurnGroup> groupBlocksByTurn(List<SessionBlock> blocks) {
  final groups = <TurnGroup>[];
  for (final block in blocks) {
    final group = groups.isEmpty ? null : groups.last;
    if (group != null && continuesResponse(group.blocks.last, block)) {
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

  return groups.map((group) {
    final last = group.blocks.last;
    final running = group.blocks.any(
      (block) => block.status == BlockStatus.running,
    );
    final completedAt = running ? null : last.createdAt;
    return TurnGroup(
      turnId: group.turnId,
      blocks: group.blocks,
      startedAt: group.startedAt,
      completedAt: completedAt,
      durationMs: _durationBetween(group.startedAt, completedAt),
      running: running,
    );
  }).toList();
}

int? _durationBetween(String? startedAt, String? completedAt) {
  if (startedAt == null || completedAt == null) return null;
  final start = DateTime.tryParse(startedAt);
  final end = DateTime.tryParse(completedAt);
  if (start == null || end == null) return null;
  return end.difference(start).inMilliseconds.clamp(0, 1 << 53);
}
