import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/tool_grouping.dart';

SessionBlock tool(
  int seq, {
  String turn = 'turn-1',
  BlockKind kind = BlockKind.tool,
  BlockStatus status = BlockStatus.ok,
}) => SessionBlock(
  id: '$seq',
  firstSeq: seq,
  lastSeq: seq,
  turnId: turn,
  kind: kind,
  status: status,
  title: 'Tool',
  body: '',
);

void main() {
  test(
    'tool groups stop at prose, turn boundaries, and the pagination pivot',
    () {
      final groups = groupConsecutiveTools([
        tool(1),
        tool(2),
        tool(3),
        tool(4, kind: BlockKind.assistant),
        tool(5),
        tool(6, turn: 'turn-2'),
        tool(7, turn: 'turn-2'),
      ], pivot: 2);
      expect(groups['1']!.map((block) => block.id), ['1', '2']);
      expect(groups['3']!.map((block) => block.id), ['3']);
      expect(groups.containsKey('4'), isFalse);
      expect(groups['5']!.map((block) => block.id), ['5']);
      expect(groups['6']!.map((block) => block.id), ['6', '7']);
    },
  );

  test('interactive and file-change tools stay outside collapsible groups', () {
    final groups = groupConsecutiveTools([
      tool(1),
      tool(2, status: BlockStatus.blocked),
      tool(3).copyWith(interactionId: 'approval'),
      tool(4).copyWith(detail: const QuestionBlockDetail(questions: [])),
      tool(5).copyWith(detail: const FileChangeBlockDetail(files: [])),
      tool(6),
    ], pivot: 0);
    expect(groups.keys, ['1', '6']);
    expect(groups['1'], hasLength(1));
    expect(groups['6'], hasLength(1));
  });
}
