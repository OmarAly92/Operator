import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

List<ConversationSnapshotModel> discardHistoricalPages(
  List<ConversationSnapshotModel> pages,
) => pages.isEmpty ? pages : pages.sublist(0, 1);

ConversationSnapshotModel? mergeConversationPages(
  List<ConversationSnapshotModel> pages,
) {
  if (pages.isEmpty) return null;
  final live = pages.first;
  final items = <String, ConversationItemModel>{};
  final turns = <String, ConversationTurnModel>{};

  for (final page in pages.reversed) {
    for (final item in page.items) {
      items[item.itemKey] = item;
    }
    for (final turn in page.turns) {
      turns[turn.id ?? ''] = turn;
    }
  }

  final mergedItems = items.values.toList()
    ..sort(
      (left, right) => (left.sequence ?? 0).compareTo(right.sequence ?? 0),
    );
  final mergedTurns = turns.values.toList()
    ..sort(
      (left, right) =>
          (left.requestedAt ?? '').compareTo(right.requestedAt ?? ''),
    );
  final oldest = pages.last;

  return live.copyWith(
    oldestSequence: oldest.oldestSequence,
    hasMoreBefore: oldest.hasMoreBefore,
    items: mergedItems,
    turns: mergedTurns,
  );
}
