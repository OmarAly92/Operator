import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/active_since.dart';

DateTime? workingSince({
  required Iterable<SessionModel> sessions,
  required String sessionId,
  required List<SessionBlock> blocks,
}) {
  final since = activeSince(sessions, sessionId);
  if (since != null) return since;
  final groups = groupBlocksByTurn(blocks, sessionActive: true);
  return DateTime.tryParse(groups.lastOrNull?.startedAt ?? '');
}
