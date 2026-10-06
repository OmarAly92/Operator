import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_fold.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

SessionBlock _b(
  String id,
  BlockKind kind, {
  String? turnId = 't-1',
  String body = 'body',
  String? createdAt,
  BlockStatus status = BlockStatus.ok,
  BlockDetail? detail,
}) => SessionBlock(
  id: id,
  firstSeq: 0,
  lastSeq: 0,
  kind: kind,
  status: status,
  turnId: turnId,
  title: id,
  body: body,
  createdAt: createdAt,
  detail: detail,
);

TurnGroup _group(List<SessionBlock> blocks, {bool running = false, int? durationMs, String? startedAt, String? completedAt}) =>
    TurnGroup(
      turnId: blocks.first.turnId,
      blocks: blocks,
      running: running,
      durationMs: durationMs,
      startedAt: startedAt,
      completedAt: completedAt,
    );

void main() {
  test('a settled turn with tools folds everything but the prompt and the final reply', () {
    final folds = turnFolds([
      _group([
        _b('p', BlockKind.prompt),
        _b('a1', BlockKind.assistant),
        _b('r', BlockKind.reasoning),
        _b('t1', BlockKind.tool),
        _b('t2', BlockKind.tool),
        _b('a2', BlockKind.assistant),
      ], durationMs: 13000),
    ]);

    expect(folds, hasLength(1));
    final fold = folds.single;
    expect(fold.id, 't-1');
    expect(fold.anchorId, 'a1');
    expect(fold.hiddenIds, ['a1', 'r', 't1', 't2']);
    expect(fold.label, 'Worked for 13s');
  });

  test('a running turn never folds', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('t', BlockKind.tool), _b('a', BlockKind.assistant)], running: true),
    ]);

    expect(folds, isEmpty);
  });

  test('a turn with only a reply does not fold', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('a', BlockKind.assistant)], durationMs: 1000),
    ]);

    expect(folds, isEmpty);
  });

  test('reasoning alone is enough to fold', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('r', BlockKind.reasoning), _b('a', BlockKind.assistant)], durationMs: 2000),
    ]);

    expect(folds.single.hiddenIds, ['r']);
  });

  test('a group that does not start with a prompt does not fold', () {
    final folds = turnFolds([
      _group([_b('t', BlockKind.tool), _b('a', BlockKind.assistant)], durationMs: 1000),
    ]);

    expect(folds, isEmpty);
  });

  test('questions and permissions stay visible', () {
    final folds = turnFolds([
      _group([
        _b('p', BlockKind.prompt),
        _b('t', BlockKind.tool),
        _b('q', BlockKind.notice, detail: const QuestionBlockDetail(questions: [])),
        _b('perm', BlockKind.permission),
        _b('a', BlockKind.assistant),
      ], durationMs: 1000),
    ]);

    expect(folds.single.hiddenIds, ['t']);
  });

  test('without a final reply every step after the prompt folds', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('t1', BlockKind.tool), _b('t2', BlockKind.tool)], durationMs: 4000),
    ]);

    expect(folds.single.hiddenIds, ['t1', 't2']);
    expect(folds.single.anchorId, 't1');
  });

  test('an empty trailing reply is not the final reply', () {
    final folds = turnFolds([
      _group([
        _b('p', BlockKind.prompt),
        _b('a1', BlockKind.assistant, body: 'answer'),
        _b('t', BlockKind.tool),
        _b('a2', BlockKind.assistant, body: '  '),
      ], durationMs: 1000),
    ]);

    expect(folds.single.hiddenIds, ['t', 'a2']);
  });

  test('the label falls back to completedAt minus startedAt', () {
    final folds = turnFolds([
      _group(
        [_b('p', BlockKind.prompt), _b('t', BlockKind.tool), _b('a', BlockKind.assistant)],
        startedAt: '2026-09-24T10:00:00Z',
        completedAt: '2026-09-24T10:02:05Z',
      ),
    ]);

    expect(folds.single.label, 'Worked for 2m 5s');
  });

  test('the label formats hours with turnElapsed', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('t', BlockKind.tool), _b('a', BlockKind.assistant)], durationMs: 12600000),
    ]);

    expect(folds.single.label, 'Worked for 3h 30m');
  });

  test('without a duration the label counts the folded steps', () {
    final folds = turnFolds([
      _group([
        _b('p', BlockKind.prompt),
        _b('t1', BlockKind.tool),
        _b('t2', BlockKind.tool),
        _b('a', BlockKind.assistant),
      ]),
    ]);

    expect(folds.single.label, 'Worked · 2 steps');
  });

  test('one folded step is singular', () {
    final folds = turnFolds([
      _group([_b('p', BlockKind.prompt), _b('t', BlockKind.tool), _b('a', BlockKind.assistant)]),
    ]);

    expect(folds.single.label, 'Worked · 1 step');
  });

  test('a turn without a turn id is keyed by its prompt', () {
    final folds = turnFolds([
      _group([
        _b('p', BlockKind.prompt, turnId: null),
        _b('t', BlockKind.tool, turnId: null),
        _b('a', BlockKind.assistant, turnId: null),
      ], durationMs: 1000),
    ]);

    expect(folds.single.id, 'p');
  });

  test('showsThinking while the running turn has streamed nothing or only reasoning', () {
    expect(showsThinking([_group([_b('p', BlockKind.prompt)], running: true)]), isTrue);
    expect(
      showsThinking([_group([_b('p', BlockKind.prompt), _b('r', BlockKind.reasoning)], running: true)]),
      isTrue,
    );
    expect(
      showsThinking([_group([_b('p', BlockKind.prompt), _b('t', BlockKind.tool)], running: true)]),
      isFalse,
    );
    expect(
      showsThinking([_group([_b('p', BlockKind.prompt), _b('a', BlockKind.assistant)], running: true)]),
      isFalse,
    );
    expect(showsThinking([_group([_b('p', BlockKind.prompt)])]), isFalse);
    expect(showsThinking(const []), isFalse);
  });
}
