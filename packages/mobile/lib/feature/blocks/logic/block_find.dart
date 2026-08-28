import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

enum BlockMatchField { displayName, summary }

class BlockMatch extends Equatable {
  const BlockMatch({required this.blockId, required this.field, required this.score, required this.ranges});

  final String blockId;
  final BlockMatchField field;
  final MatchScore score;
  final List<MatchRange> ranges;

  @override
  List<Object?> get props => [blockId, field, score, ranges];
}

class BlockFilterResult extends Equatable {
  const BlockFilterResult({required this.blocks, required this.matchIds, required this.hiddenCount});

  final List<SessionBlock> blocks;
  final Set<String> matchIds;
  final int hiddenCount;

  @override
  List<Object?> get props => [blocks, matchIds, hiddenCount];
}

sealed class BlockFind {
  static List<String> searchFields(SessionBlock block) {
    final display = blockDisplay(block);
    return [display.displayName, display.summary];
  }

  static List<BlockMatch> matches(List<SessionBlock> blocks, String query) {
    if (query.trim().isEmpty) return const [];
    final results = <BlockMatch>[];
    void visit(SessionBlock block) {
      final match = _matchBlock(block, query);
      if (match != null) results.add(match);
      for (final child in block.children ?? const <SessionBlock>[]) {
        visit(child);
      }
    }

    for (final block in blocks) {
      visit(block);
    }
    return results;
  }

  static BlockMatch? _matchBlock(SessionBlock block, String query) {
    BlockMatch? best;
    for (final entry in searchFields(block).asMap().entries) {
      final score = TextMatch.score(query, entry.value, subsequence: false);
      if (score == null) continue;
      final candidate = BlockMatch(
        blockId: block.id,
        field: entry.key == 0 ? BlockMatchField.displayName : BlockMatchField.summary,
        score: score,
        ranges: TextMatch.ranges(query, entry.value, score),
      );
      if (best == null || TextMatch.compare(candidate.score, best.score) < 0) best = candidate;
    }
    return best;
  }

  static BlockFilterResult filter(List<SessionBlock> blocks, String query, int contextBlocks) {
    if (query.trim().isEmpty) return BlockFilterResult(blocks: blocks, matchIds: const {}, hiddenCount: 0);
    final results = matches(blocks, query);
    final matchIds = results.map((match) => match.blockId).toSet();
    final topLevelIndex = <String, int>{};
    void indexBlock(SessionBlock block, int index) {
      topLevelIndex[block.id] = index;
      for (final child in block.children ?? const <SessionBlock>[]) {
        indexBlock(child, index);
      }
    }

    for (var index = 0; index < blocks.length; index += 1) {
      indexBlock(blocks[index], index);
    }
    final keep = <int>{};
    final context = contextBlocks < 0 ? 0 : contextBlocks;
    for (final match in results) {
      final index = topLevelIndex[match.blockId];
      if (index == null) continue;
      final start = (index - context) < 0 ? 0 : index - context;
      final end = (index + context) >= blocks.length ? blocks.length - 1 : index + context;
      for (var candidate = start; candidate <= end; candidate += 1) {
        keep.add(candidate);
      }
    }
    final filtered = <SessionBlock>[for (var index = 0; index < blocks.length; index += 1) if (keep.contains(index)) blocks[index]];
    return BlockFilterResult(blocks: filtered, matchIds: matchIds, hiddenCount: blocks.length - filtered.length);
  }

  static String? nextMatchId(List<BlockMatch> matches, String? currentId, {required bool forward}) {
    if (matches.isEmpty) return null;
    final currentIndex = currentId == null ? -1 : matches.indexWhere((match) => match.blockId == currentId);
    if (currentIndex == -1) return forward ? matches.first.blockId : matches.last.blockId;
    return matches[(currentIndex + (forward ? 1 : -1) + matches.length) % matches.length].blockId;
  }
}
