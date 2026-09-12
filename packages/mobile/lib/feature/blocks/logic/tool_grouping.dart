import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

Map<String, List<SessionBlock>> groupConsecutiveTools(
  List<SessionBlock> blocks, {
  required int pivot,
}) {
  final groups = <String, List<SessionBlock>>{};
  var run = <SessionBlock>[];
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    if (block.kind != BlockKind.tool ||
        block.status == BlockStatus.blocked ||
        block.interactionId != null ||
        block.detail is QuestionBlockDetail ||
        block.detail is FileChangeBlockDetail) {
      run = [];
      continue;
    }
    if (index == pivot || (run.isNotEmpty && run.last.turnId != block.turnId)) {
      run = [];
    }
    run.add(block);
    groups[block.id] = run;
  }
  return groups;
}
