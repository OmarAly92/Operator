import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

class TurnFold extends Equatable {
  const TurnFold({required this.id, required this.label, required this.anchorId, required this.hiddenIds});

  final String id;
  final String label;
  final String anchorId;
  final List<String> hiddenIds;

  @override
  List<Object?> get props => [id, label, anchorId, hiddenIds];
}

List<TurnFold> turnFolds(List<TurnGroup> groups) {
  final folds = <TurnFold>[];
  for (final group in groups) {
    final fold = _foldOf(group);
    if (fold != null) folds.add(fold);
  }
  return folds;
}

bool showsThinking(List<TurnGroup> groups) {
  if (groups.isEmpty) return false;
  final last = groups.last;
  if (!last.running) return false;
  final kind = last.blocks.last.kind;
  return kind == BlockKind.prompt || kind == BlockKind.reasoning;
}

TurnFold? _foldOf(TurnGroup group) {
  if (group.running || group.blocks.first.kind != BlockKind.prompt) return null;
  final reply = _finalReply(group.blocks);
  final hidden = <SessionBlock>[
    for (final block in group.blocks)
      if (block != reply && foldableInTurn(block)) block,
  ];
  if (!hidden.any((block) => block.kind == BlockKind.tool || block.kind == BlockKind.reasoning)) return null;
  return TurnFold(
    id: group.turnId ?? group.blocks.first.id,
    label: _label(group, hidden.length),
    anchorId: hidden.first.id,
    hiddenIds: [for (final block in hidden) block.id],
  );
}

bool foldableInTurn(SessionBlock block) =>
    block.kind != BlockKind.prompt && block.kind != BlockKind.permission && block.detail is! QuestionBlockDetail;

SessionBlock? _finalReply(List<SessionBlock> blocks) {
  for (var index = blocks.length - 1; index >= 0; index--) {
    final block = blocks[index];
    if (block.kind == BlockKind.assistant && block.detail is! FileChangeBlockDetail && block.body.trim().isNotEmpty) {
      return block;
    }
  }
  return null;
}

String _label(TurnGroup group, int steps) {
  final ms = group.durationMs ?? _between(group.startedAt, group.completedAt);
  if (ms != null) return 'Worked for ${turnElapsed(Duration(milliseconds: ms))}';
  return 'Worked · $steps ${steps == 1 ? 'step' : 'steps'}';
}

int? _between(String? startedAt, String? completedAt) {
  final start = startedAt == null ? null : DateTime.tryParse(startedAt);
  final end = completedAt == null ? null : DateTime.tryParse(completedAt);
  if (start == null || end == null) return null;
  return end.difference(start).inMilliseconds;
}
