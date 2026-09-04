import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

SessionBlock _block(String id, BlockKind kind, BlockStatus status, {String? model}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: kind,
  status: status,
  title: id,
  body: '',
  model: model,
);

void main() {
  test('a turn carries the first model any of its blocks reported', () {
    final groups = groupBlocksByTurn([
      _block('p', BlockKind.prompt, BlockStatus.ok),
      _block('a', BlockKind.assistant, BlockStatus.ok, model: 'claude-sonnet-5'),
      _block('b', BlockKind.assistant, BlockStatus.ok, model: 'claude-opus-5'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.model, 'claude-sonnet-5');
  });

  test('an active session marks only the last turn as running', () {
    final groups = groupBlocksByTurn([
      _block('p1', BlockKind.prompt, BlockStatus.ok),
      _block('a1', BlockKind.assistant, BlockStatus.ok),
      _block('p2', BlockKind.prompt, BlockStatus.ok),
      _block('a2', BlockKind.assistant, BlockStatus.ok),
    ], sessionActive: true);

    expect(groups, hasLength(2));
    expect(groups.first.running, isFalse);
    expect(groups.last.running, isTrue);
    expect(groups.last.completedAt, isNull);
  });

  test('an idle session leaves every turn finished', () {
    final groups = groupBlocksByTurn([
      _block('p1', BlockKind.prompt, BlockStatus.ok),
      _block('a1', BlockKind.assistant, BlockStatus.ok),
    ]);

    expect(groups.single.running, isFalse);
  });
}
